import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Query.checkLinks` and the old board names at read time (divergence.md M9): the class of each stored link
/// (`OK`, `OLD_NAME`, `DANGLING`, `MISSING_NODE`), the field of each link (`dependsOn`, an assignee URI, a task URL in
/// a body, the line of a moved task), and the `OLD_BOARD_NAME` warning of a read through an old name.
///
/// Each test makes real git repos in a ``GitSandbox``. The engines read the worktree tops and the board keys from git.
@Suite("checkLinks, and old board names at read time", .watcherBudget)
struct CheckLinksTests {
    /// The selection of each link of `Query.checkLinks`.
    static let checkSelection = "{ board node field target status currentName }"

    // MARK: - Helpers

    /// One link of a `Query.checkLinks` response.
    struct Check: Equatable {
        /// The key of the board that holds the link.
        let board: String

        /// The full URI of the task that holds the link.
        let node: String

        /// The field of the link, for example `DEPENDS_ON`.
        let field: String

        /// The link as the board stores it.
        let target: String

        /// The class of the link, for example `OK`.
        let status: String

        /// The current name of the board that the link names, or `nil` when no board has the name.
        let currentName: String?

        /// Reads one link of a response.
        ///
        /// - Parameter object: The link object of the response.
        /// - Throws: An error when a field that is not nullable has no text.
        init(_ object: [String: Any]) throws {
            board = try #require(object["board"] as? String)
            node = try #require(object["node"] as? String)
            field = try #require(object["field"] as? String)
            target = try #require(object["target"] as? String)
            status = try #require(object["status"] as? String)
            currentName = object["currentName"] as? String
        }

        /// Makes the expected value of one link.
        ///
        /// - Parameters:
        ///   - board: The key of the board that holds the link.
        ///   - node: The full URI of the task that holds the link.
        ///   - field: The field of the link.
        ///   - target: The link as the board stores it.
        ///   - status: The class of the link.
        ///   - currentName: The current name of the board that the link names.
        init(board: String, node: String, field: String, target: String, status: String, currentName: String?) {
            self.board = board
            self.node = node
            self.field = field
            self.target = target
            self.status = status
            self.currentName = currentName
        }
    }

    /// Runs `Query.checkLinks`.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the field, for example `(boards: ["lib"])`, or the empty text.
    ///   - graph: The engine.
    /// - Returns: The links of the response, and the response JSON text.
    /// - Throws: An error when the response has no list of links.
    static func checks(
        with arguments: String = "",
        on graph: KanbanGraph
    ) async throws -> (checks: [Check], response: String) {
        let response = try await KanbanGraphTests.execute("{ checkLinks\(arguments) \(checkSelection) }", on: graph)
        let objects = try #require(KanbanGraphTests.data(of: response)["checkLinks"] as? [[String: Any]], "\(response)")
        return (try objects.map(Check.init), response)
    }

    /// Gives the message of each `OLD_BOARD_NAME` warning of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The messages, in the order of the response.
    /// - Throws: An error when the response is not a JSON object.
    static func oldNameWarnings(in response: String) throws -> [String] {
        try ResponseWarningsTests.warnings(of: response)
            .filter { warning in warning.code == OldBoardName.warningCode }
            .compactMap(\.message)
    }

    /// Two repos side by side: a task of the current repo depends on a task of the related repo, and then the
    /// `origin` of the related repo changes. The stored link thus has the old git key of the related board.
    struct RenamedLib {
        /// The repos.
        let repos: CrossRepoFixture.SideBySide

        /// The full URI of the task of the current repo.
        let task: String

        /// The full URI of the task of the related repo, with the old git key.
        let target: String

        /// The old git key of the related board.
        let oldKey: String

        /// The current git key of the related board.
        let newKey: String
    }

    /// Makes the repos of ``RenamedLib``. The engines of the setup are closed when the function returns.
    ///
    /// - Parameter isDone: `true` to complete the task of the related repo before the remote change.
    /// - Returns: The repos, the tasks, and the two keys of the related board.
    /// - Throws: An error when a git command fails, or when a call fails.
    static func makeRenamedLib(completingTarget isDone: Bool) async throws -> RenamedLib {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        if isDone {
            try await CrossRepoUndoTests.runWithNoErrors(
                CommentTests.nodeField(MutationName.completeTask, naming: target),
                on: lib
            )
        }
        await lib.close()
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        await app.close()
        try await BoardIDTests.setNewRemote(ofRepoAt: repos.lib)
        return RenamedLib(
            repos: repos,
            task: task,
            target: target,
            oldKey: try CrossRepoWriteTests.libKey(),
            newKey: try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin)
        )
    }

    /// Expects that a response has one `OLD_BOARD_NAME` warning, and that the warning names the old name and the
    /// current name of the related board of a ``RenamedLib``.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - renamed: The repos and the keys of the related board.
    /// - Throws: An error when the response is not a JSON object.
    static func expectOneOldNameWarning(in response: String, for renamed: RenamedLib) throws {
        let warnings = try oldNameWarnings(in: response)
        #expect(warnings.count == 1, "\(response)")
        let message = try #require(warnings.first)
        #expect(message.contains(renamed.oldKey) && message.contains(renamed.newKey), "\(message)")
    }

    // MARK: - Old names at read time

    @Test("A task that depends on a task through an old board name is ready when that task is done, and it warns")
    func oldNameDependencyIsReadyWithWarning() async throws {
        let renamed = try await Self.makeRenamedLib(completingTarget: true)
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        let query = try CrossRepoReadTests.query(of: renamed.task, selecting: CrossRepoReadTests.readySelection)
        let response = try await KanbanGraphTests.execute(query, on: app)
        await app.close()
        let task = try #require(KanbanGraphTests.object(named: "board", in: response)["task"] as? [String: Any])
        #expect(task["ready"] as? Bool == true, "\(response)")
        try Self.expectOneOldNameWarning(in: response, for: renamed)
    }

    @Test("board(id:) with an old name gives the board that has the name now, with its current names, and warns")
    func boardByOldNameGivesCurrentNames() async throws {
        let renamed = try await Self.makeRenamedLib(completingTarget: false)
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        let response = try await KanbanGraphTests.execute(
            #"{ board(id: "\#(renamed.oldKey)") { key names path } }"#,
            on: app
        )
        await app.close()
        let board = try KanbanGraphTests.object(named: "board", in: response)
        #expect(board["key"] as? String == renamed.newKey)
        #expect((board["names"] as? [String])?.first == renamed.newKey)
        #expect((board["names"] as? [String])?.contains(renamed.oldKey) == true)
        #expect(board["path"] as? String == renamed.repos.lib.path)
        try Self.expectOneOldNameWarning(in: response, for: renamed)
    }

    // MARK: - Link classes

    @Test("checkLinks gives OK for a dependsOn link with the current name of a related board")
    func currentNameLinkIsOK() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let target = try await CrossRepoFixture.addTask(with: "", on: GitGraphFixture.makeGraph(at: repos.lib))
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let result = try await Self.checks(on: app)
        await app.close()
        let libKey = try CrossRepoWriteTests.libKey()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: task,
            field: "DEPENDS_ON",
            target: target,
            status: "OK",
            currentName: libKey
        )
        #expect(result.checks == [expected], "\(result.response)")
        #expect(try KanbanGraphTests.object(of: result.response)["extensions"] == nil, "\(result.response)")
    }

    @Test("checkLinks gives OLD_NAME and the current name for a link with an old board name, and warns")
    func oldNameLinkIsOldName() async throws {
        let renamed = try await Self.makeRenamedLib(completingTarget: false)
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        let result = try await Self.checks(on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: renamed.task,
            field: "DEPENDS_ON",
            target: renamed.target,
            status: "OLD_NAME",
            currentName: renamed.newKey
        )
        #expect(result.checks == [expected], "\(result.response)")
        try Self.expectOneOldNameWarning(in: result.response, for: renamed)
    }

    @Test("checkLinks gives DANGLING and no current name for a link to a board that no scan finds")
    func missingBoardLinkIsDangling() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let result = try await Self.checks(on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: task,
            field: "DEPENDS_ON",
            target: target,
            status: "DANGLING",
            currentName: nil
        )
        #expect(result.checks == [expected], "\(result.response)")
    }

    @Test("checkLinks gives MISSING_NODE for a link to a task that the found board does not have")
    func missingTaskLinkIsMissingNode() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        _ = try await CrossRepoFixture.addTask(with: "", on: GitGraphFixture.makeGraph(at: repos.lib))
        let libKey = try CrossRepoWriteTests.libKey()
        let target = NodeURI(boardKey: libKey, ref: .task(ULID())).description
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let result = try await Self.checks(on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: task,
            field: "DEPENDS_ON",
            target: target,
            status: "MISSING_NODE",
            currentName: libKey
        )
        #expect(result.checks == [expected], "\(result.response)")
    }

    // MARK: - Link fields

    @Test("checkLinks lists a task URL in the body of a task with the field BODY")
    func bodyURLIsBodyLink() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let target = try await CrossRepoFixture.addTask(with: "", on: GitGraphFixture.makeGraph(at: repos.lib))
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let task = try await CrossRepoFixture.addTask(with: #"body: "Needs \#(target) first.""#, on: app)
        let result = try await Self.checks(on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: task,
            field: "BODY",
            target: target,
            status: "OK",
            currentName: try CrossRepoWriteTests.libKey()
        )
        #expect(result.checks == [expected], "\(result.response)")
    }

    @Test("checkLinks lists the line of a moved task with the field TOMBSTONE")
    func movedLineIsTombstoneLink() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let moved = try await CrossRepoTransferTests.transfer(
            MutationName.moveTask,
            old,
            with: try CrossRepoTransferTests.libBoard(),
            on: app
        )
        let result = try await Self.checks(on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.appKey(),
            node: old,
            field: "TOMBSTONE",
            target: moved,
            status: "OK",
            currentName: try CrossRepoWriteTests.libKey()
        )
        #expect(result.checks == [expected], "\(result.response)")
    }

    @Test("checkLinks(board:) with the name of a related repo lists the assignee URI of its task as ASSIGNEE")
    func remoteAssigneeIsAssigneeLink() async throws {
        let transfer = try await CrossRepoTransferTests.makeAssignedTransfer(MutationName.moveTask)
        let app = try GitGraphFixture.makeGraph(at: transfer.repos.app)
        let result = try await Self.checks(with: #"(board: "\#(BoardLocatorTests.libName)")"#, on: app)
        await app.close()
        let expected = Check(
            board: try CrossRepoWriteTests.libKey(),
            node: transfer.written,
            field: "ASSIGNEE",
            target: transfer.actor,
            status: "OK",
            currentName: try CrossRepoWriteTests.appKey()
        )
        #expect(result.checks == [expected], "\(result.response)")
    }

    // MARK: - Units

    /// The reason of the board that cannot be read in the unit tests.
    static let unreadableReason = "permission denied"

    /// Makes a related board that cannot be read, with the key of ``BoardLocatorTests/newOrigin``, whose board log
    /// recorded the git key of ``BoardLocatorTests/libOrigin``.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a remote URL is not valid.
    static func unreadableRenamedLib() throws -> LinkedBoard {
        var board = BoardNode(fields: GraphTests.fields)
        board.gitKey = try CrossRepoWriteTests.libKey()
        let key = try BoardLocatorTests.key(of: BoardLocatorTests.newOrigin)
        let directory = URL(filePath: "/\(BoardLocatorTests.libName)", directoryHint: .isDirectory)
        let copy = BoardCopy(directory: directory, key: key, isEnabled: true, names: BoardNames(key: key, board: board))
        return .unreadable(UnreadableBoard(copy: copy, reason: unreadableReason, effect: .warning))
    }

    @Test("A link to a board that cannot be read gets the class of its name only: OLD_NAME or OK")
    func unreadableBoardGivesClassOfName() throws {
        let linked = try Self.unreadableRenamedLib()
        let newKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin)
        let byOldName = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID()))
        let byNewName = NodeURI(boardKey: newKey, ref: .task(ULID()))
        let old = linked.check(of: byOldName)
        let current = linked.check(of: byNewName)
        #expect(old.status == .oldName)
        #expect(current.status == .ok)
        #expect([old.currentName, current.currentName] == [newKey, newKey])
    }

    @Test("The moved line parse reads a line of a move that ends with CRLF, and skips a line that is no URI")
    func movedLineParseReadsCRLFLine() throws {
        let moved = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID()))
        let body = "Notes.\n\n\(MovedTaskLine.text(pointingTo: moved))\r\nMoved to the next sprint."
        #expect(MovedTaskLine.targets(in: body) == [moved])
    }
}
