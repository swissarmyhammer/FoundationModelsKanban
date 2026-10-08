import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

extension Design {
    /// Tests that local data is portable (plan.md §1 item 9, §3.2, §11, §12 items 4 and 18): the log of a board
    /// holds no key of its own board, so a move of the repo changes no stored data.
    ///
    /// Each test makes a real git repo in a ``GitSandbox`` and an engine that reads the board key from git. The engine
    /// writes a board through full URIs with the current key: a tag, a task that is done, and a second task with the
    /// tag, a dependency on the first task, and a comment. A move test then moves the repo, and a new engine reads the
    /// board with the new key.
    @Suite("Design: portability of the local data")
    struct PortabilityTests {
        /// A move of a repo that changes the board key.
        enum RepoMove: CaseIterable, Sendable, CustomTestStringConvertible {
            /// The repo gets a new `origin` remote.
            case newOrigin

            /// The repo has no remote, and its directory gets a new name.
            case newDirectoryName

            /// The name of the repo directory before the move.
            static let repoName = "moved-repo"

            /// The name of the repo directory after a ``newDirectoryName`` move.
            static let movedName = "renamed-repo"

            /// The `origin` of the repo after a ``newOrigin`` move.
            static let newOriginURL = "git@gitlab.com:new-owner/moved-repo.git"

            var testDescription: String {
                switch self {
                case .newOrigin: "a new origin"
                case .newDirectoryName: "a new directory name"
                }
            }

            /// Makes the repo before the move.
            ///
            /// - Parameter sandbox: The sandbox of the test.
            /// - Returns: The repo directory.
            func makeRepo(in sandbox: GitSandbox) async throws -> URL {
                switch self {
                case .newOrigin: try await sandbox.makeRepo(named: Self.repoName, origin: BoardKeyTests.httpsRemote)
                case .newDirectoryName: try await sandbox.makeRepo(named: Self.repoName)
                }
            }

            /// Moves the repo.
            ///
            /// - Parameters:
            ///   - repo: The repo directory before the move.
            ///   - sandbox: The sandbox of the test.
            /// - Returns: The repo directory after the move.
            func move(_ repo: URL, in sandbox: GitSandbox) async throws -> URL {
                switch self {
                case .newOrigin:
                    try await sandbox.runGit(
                        withArguments: ["remote", "set-url", "origin", Self.newOriginURL],
                        in: repo
                    )
                    return repo
                case .newDirectoryName:
                    let moved = sandbox.root.appending(path: Self.movedName, directoryHint: .isDirectory)
                    try FileManager.default.moveItem(at: repo, to: moved)
                    return moved
                }
            }

            /// The board key after the move.
            ///
            /// - Returns: The key.
            func movedKey() throws -> BoardKey {
                switch self {
                case .newOrigin: try BoardKey(remoteURL: Self.newOriginURL)
                case .newDirectoryName: BoardKey(localDirectoryName: Self.movedName)
                }
            }
        }

        /// The board that ``writeBoard(on:)`` writes.
        struct WrittenBoard {
            /// The task that is done.
            let done: ULID

            /// The task with the tag, the dependency, and the comment.
            let dependent: ULID
        }

        /// The fields of a task that read each edge of the task, and `ready`, which reads the `dependsOn` edges.
        static let edgeFields = "ready tags { id } dependsOn { id } comments { task { id } author { id } }"

        /// A query that reads the whole board with the edges of each task.
        static let boardQuery = "{ board { key tags { id } columns { id } actors { id } tasks(excludeDone: false) "
            + "{ edges { node { id column { id } \(edgeFields) } } } } }"

        // MARK: - Helpers

        /// Runs one mutation field on an engine, and gives the id that the field returns.
        ///
        /// - Parameters:
        ///   - field: The mutation field. Its selection is `{ id }`.
        ///   - name: The name of the mutation field, which is the key of the field in the response.
        ///   - graph: The engine.
        /// - Returns: The full URI of the node of the field.
        static func id(runningField field: String, named name: String, on graph: KanbanGraph) async throws -> String {
            let response = try KanbanGraphTests.object(of: try await CommentTests.run(field, on: graph))
            let data = try #require(response["data"] as? [String: Any])
            let node = try #require(data[name] as? [String: Any])
            return try #require(node["id"] as? String)
        }

        /// Writes the board of the tests through the full URIs that the engine returns: a tag, a task with the tag,
        /// a second task that depends on the first, a comment on the second task, and then completes the first task.
        ///
        /// - Parameter graph: The engine of the repo.
        /// - Returns: The tasks of the board.
        static func writeBoard(on graph: KanbanGraph) async throws -> WrittenBoard {
            let tag = try await id(
                runningField: TagMutationTests.addTag(named: TagMutationTests.bug),
                named: MutationName.addTag,
                on: graph
            )
            let done = try await id(
                runningField: AddUpdateTaskTests.addTask(with: ""),
                named: MutationName.addTask,
                on: graph
            )
            let input = "tags: \(AddUpdateTaskTests.list(of: [tag])), dependsOn: \(AddUpdateTaskTests.list(of: [done]))"
            let dependent = try await id(
                runningField: AddUpdateTaskTests.addTask(with: input),
                named: MutationName.addTask,
                on: graph
            )
            _ = try await CommentTests.run(CommentTests.addComment(to: dependent), on: graph)
            _ = try await CommentTests.run(CommentTests.nodeField(MutationName.completeTask, naming: done), on: graph)
            return WrittenBoard(
                done: try AddUpdateTaskTests.firstTask(in: done),
                dependent: try AddUpdateTaskTests.firstTask(in: dependent)
            )
        }

        /// Reads the text of each node log of a board.
        ///
        /// - Parameter root: The root directory of the repo.
        /// - Returns: The text of each log, by the local ref of its node.
        static func logTexts(inRepoAt root: URL) throws -> [LocalRef: String] {
            let log = EventLog(repositoryAt: root)
            let refs = try log.nodeFileSignatures().keys
            return Dictionary(
                uniqueKeysWithValues: try refs.map { ref in
                    (ref, try String(contentsOf: log.fileURL(for: ref), encoding: .utf8))
                }
            )
        }

        /// Gives the full URI of a node of a board.
        ///
        /// - Parameters:
        ///   - ref: The local ref of the node.
        ///   - key: The key of the board.
        /// - Returns: The URI text.
        static func uri(of ref: LocalRef, inBoard key: BoardKey) -> String {
            NodeURI(boardKey: key.description, ref: ref).description
        }

        /// Gives the response to the query of the edges of the dependent task, as the board with a key gives it.
        ///
        /// - Parameters:
        ///   - board: The written board.
        ///   - key: The key of the board.
        /// - Returns: The response JSON text, with sorted keys.
        static func edgesResponse(of board: WrittenBoard, inBoard key: BoardKey) -> String {
            let dependent = uri(of: .task(board.dependent), inBoard: key)
            let author = uri(of: KanbanGraphTests.sessionActor.ref, inBoard: key)
            let comment = #"{"author":{"id":"\#(author)"},"task":{"id":"\#(dependent)"}}"#
            let done = uri(of: .task(board.done), inBoard: key)
            let tag = uri(of: .tag(slug: TagMutationTests.bug), inBoard: key)
            let task = #"{"comments":[\#(comment)],"dependsOn":[{"id":"\#(done)"}],"ready":true,"#
                + #""tags":[{"id":"\#(tag)"}]}"#
            return #"{"data":{"board":{"task":\#(task)}}}"#
        }

        // MARK: - Repo move

        @Test("A move of the repo changes no log file", arguments: RepoMove.allCases)
        func moveChangesNoLogFile(move: RepoMove) async throws {
            let sandbox = try GitSandbox()
            let repo = try await move.makeRepo(in: sandbox)
            let graph = try GitGraphFixture.makeGraph(at: repo)
            _ = try await Self.writeBoard(on: graph)
            await graph.close()
            let before = try Self.logTexts(inRepoAt: repo)
            let moved = try await move.move(repo, in: sandbox)
            _ = try await KanbanGraphTests.execute(Self.boardQuery, on: GitGraphFixture.makeGraph(at: moved))
            #expect(try Self.logTexts(inRepoAt: moved) == before)
        }

        @Test("After a move of the repo, each id has the new key, and each edge resolves", arguments: RepoMove.allCases)
        func moveGivesNewKeyAndKeepsEdges(move: RepoMove) async throws {
            let sandbox = try GitSandbox()
            let repo = try await move.makeRepo(in: sandbox)
            let oldKey = try await BoardKey.read(fromRepoAt: repo)
            let graph = try GitGraphFixture.makeGraph(at: repo)
            let board = try await Self.writeBoard(on: graph)
            let before = try await KanbanGraphTests.execute(Self.boardQuery, on: graph)
            await graph.close()
            let moved = try await move.move(repo, in: sandbox)
            let newKey = try move.movedKey()
            #expect(try await BoardKey.read(fromRepoAt: moved) == newKey)
            let movedGraph = try GitGraphFixture.makeGraph(at: moved)
            let after = try await KanbanGraphTests.execute(Self.boardQuery, on: movedGraph)
            #expect(after == before.replacingOccurrences(of: oldKey.description, with: newKey.description))
            let edgesQuery = CommentTests.taskQuery(of: board.dependent, selecting: "{ \(Self.edgeFields) }")
            let edges = try await KanbanGraphTests.execute(edgesQuery, on: movedGraph)
            #expect(edges == Self.edgesResponse(of: board, inBoard: newKey))
        }

        // MARK: - Stored form

        @Test("After writes through full URIs with the current key, no log line holds the key of its own board")
        func noLogLineHoldsBoardKey() async throws {
            let sandbox = try GitSandbox()
            let repo = try await RepoMove.newOrigin.makeRepo(in: sandbox)
            let key = try await BoardKey.read(fromRepoAt: repo)
            _ = try await Self.writeBoard(on: GitGraphFixture.makeGraph(at: repo))
            let texts = try Self.logTexts(inRepoAt: repo)
            #expect(!texts.isEmpty)
            for (ref, text) in texts {
                #expect(!text.contains(key.description), "\(ref)")
                #expect(!text.contains(NodeURI.scheme), "\(ref)")
            }
        }

        @Test("A full URI with the current key in the input is stored as a local ref")
        func currentKeyURIIsStoredAsLocalRef() async throws {
            let sandbox = try GitSandbox()
            let repo = try await RepoMove.newOrigin.makeRepo(in: sandbox)
            let board = try await Self.writeBoard(on: GitGraphFixture.makeGraph(at: repo))
            let events = try BoardMutationTests.events(of: .task(board.dependent), inRepoAt: repo)
            let added = try #require(events.first).patch.add
            #expect(added[PropertyName.tags] == AddUpdateTaskTests.tagRefs(TagMutationTests.bug))
            #expect(added[PropertyName.dependsOn] == [.local(.task(board.done))])
        }
    }
}
