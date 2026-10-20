import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Mutation.collectBoards` (divergence.md M9): the union of the node logs of each source board in the target
/// board, one node for each slug, the `collected` names of the target, the link repairs, the removal of each source
/// `.kanban/`, `dryRun`, a target with no board, a source of the old Rust kanban, `undo`, and the links of other
/// boards.
///
/// Each test makes its folders in a ``GitSandbox``, which is not in a git repo. Each board is a bare folder, so its key
/// is its board ID. Each engine of a test has its own ULID source, so that two boards never mint the same ULID.
@Suite("collectBoards", .watcherBudget)
struct CollectBoardsTests {
    /// The selection of `Mutation.collectBoards`.
    static let collectSelection = """
        { target sources { path names } slugMerges { node boards } conflicts { node field winner values } \
        repairs { node field target status newTarget } otherLinks { board node target status currentName } dryRun }
        """

    /// The name of the folder of the first source board.
    static let firstSourceName = "alpha"

    /// The name of the folder of the second source board.
    static let secondSourceName = "beta"

    /// The name of the folder of the target board.
    static let targetName = "combined"

    /// The name of the folder of a board that is not a source and not the target.
    static let otherName = "other"

    /// The new name of the `todo` column in the second source board, so that the two sources disagree on the name.
    static let renamedTodo = "Backlog"

    /// The slug of the column that each new board has first.
    static let todoSlug = "todo"

    /// The end of the full URI of the `todo` column of a board.
    static let todoSuffix = "\(LocalRef.separator)\(LocalRef.column(slug: todoSlug))"

    /// The number of boards that give the `todo` column a different name: the two sources.
    static let disagreeingBoardCount = 2

    // MARK: - Helpers

    /// One source board of a test: its folder, its board ID, and the full URI of its task.
    struct SourceBoard {
        /// The folder of the board.
        let folder: URL

        /// The primary board ID of the board.
        let id: String

        /// The full URI of the task of the board, with the board ID as its key.
        let task: String
    }

    /// Makes a bare folder board with one task and one comment on the task, and closes its engine.
    ///
    /// - Parameters:
    ///   - name: The name of the folder.
    ///   - sandbox: The sandbox of the test.
    ///   - ids: The ULID source of the engine of the board.
    ///   - input: The fields of the `addTask` input after the title, for example a `dependsOn` field.
    ///   - fields: More mutation fields that run after the task, for example a column rename.
    /// - Returns: The board.
    /// - Throws: An error when the folder cannot be made, or when a call fails.
    static func makeSourceBoard(
        named name: String,
        in sandbox: GitSandbox,
        mintingFrom ids: FixedULIDSource,
        with input: String = "",
        running fields: [String] = []
    ) async throws -> SourceBoard {
        let folder = try GitSandbox.makeFolder(named: name, in: sandbox.root)
        let graph = try GitGraphFixture.makeGraph(at: folder, mintingFrom: ids)
        let task = try await CrossRepoFixture.addTask(with: input, on: graph)
        try await CrossRepoUndoTests.runWithNoErrors(CommentTests.addComment(to: task), on: graph)
        for field in fields {
            try await CrossRepoUndoTests.runWithNoErrors(field, on: graph)
        }
        await graph.close()
        return SourceBoard(folder: folder, id: try BoardIDTests.boardID(inRepoAt: folder), task: task)
    }

    /// The two source boards and the empty target folder of a test.
    struct Fixture {
        /// The sandbox of the test. It removes the folders when the test ends.
        let sandbox: GitSandbox

        /// The first source board.
        let first: SourceBoard

        /// The second source board. Its task depends on the task of the first source board, and its `todo` column
        /// has the name ``renamedTodo``.
        let second: SourceBoard

        /// The target folder. It has no `.kanban/`.
        let target: URL

        /// The board refs of the two sources: the path of each folder.
        var sourcePaths: [String] {
            [first.folder.path, second.folder.path]
        }
    }

    /// Makes the two source boards and the empty target folder.
    ///
    /// - Returns: The fixture.
    /// - Throws: An error when a folder cannot be made, or when a call fails.
    static func makeFixture() async throws -> Fixture {
        let sandbox = try GitSandbox()
        let first = try await makeSourceBoard(
            named: firstSourceName,
            in: sandbox,
            mintingFrom: KanbanGraphTests.mutationIDs
        )
        let second = try await makeSourceBoard(
            named: secondSourceName,
            in: sandbox,
            mintingFrom: GitGraphFixture.secondEngineIDs,
            with: CrossRepoFixture.dependsOnInput(first.task),
            running: [#"updateColumn(input: { id: "\#(todoSlug)", name: "\#(renamedTodo)" }) { name }"#]
        )
        let target = try GitSandbox.makeFolder(named: targetName, in: sandbox.root)
        return Fixture(sandbox: sandbox, first: first, second: second, target: target)
    }

    /// Makes the engine of the target folder.
    ///
    /// - Parameter fixture: The fixture of the test.
    /// - Returns: The engine. The caller closes it.
    /// - Throws: An error when the engine cannot start.
    static func makeTargetGraph(of fixture: Fixture) throws -> KanbanGraph {
        try GitGraphFixture.makeGraph(at: fixture.target, mintingFrom: GitGraphFixture.thirdEngineIDs)
    }

    /// Makes a `collectBoards` field.
    ///
    /// - Parameters:
    ///   - sources: The board refs of the sources.
    ///   - options: The other arguments, for example `dryRun: true`, or `""` for none.
    /// - Returns: The field with ``collectSelection``.
    static func collectField(of sources: [String], with options: String = "") -> String {
        "\(MutationName.collectBoards)(sources: \(AddUpdateTaskTests.list(of: sources)) \(options)) \(collectSelection)"
    }

    /// Runs `collectBoards` with no error.
    ///
    /// - Parameters:
    ///   - sources: The board refs of the sources.
    ///   - options: The other arguments, for example `dryRun: true`, or `""` for none.
    ///   - graph: The engine.
    /// - Returns: The `collectBoards` object of the response.
    /// - Throws: An error when the response has an error or no object.
    static func collect(
        _ sources: [String],
        with options: String = "",
        on graph: KanbanGraph
    ) async throws -> [String: Any] {
        let response = try await CrossRepoUndoTests.runWithNoErrors(collectField(of: sources, with: options), on: graph)
        return try KanbanGraphTests.object(named: MutationName.collectBoards, in: response)
    }

    /// Gives the list of objects of one field of a `collectBoards` object.
    ///
    /// - Parameters:
    ///   - key: The name of the field, for example `slugMerges`.
    ///   - report: The `collectBoards` object.
    /// - Returns: The objects.
    /// - Throws: An error when the field is not a list of objects.
    static func objects(_ key: String, in report: [String: Any]) throws -> [[String: Any]] {
        try #require(report[key] as? [[String: Any]], "\(report)")
    }

    /// Reads the ids of the columns and the ids and comment bodies of the tasks of the current board.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The full URI of each column in board order, and the ULID of each task with the bodies of its
    ///   comments.
    /// - Throws: An error when the response has no board.
    static func board(on graph: KanbanGraph) async throws -> (columns: [String], tasks: [ULID: [String]]) {
        let query = "{ board { columns { id } tasks { edges { node { id comments { body } } } } } }"
        let response = try await KanbanGraphTests.execute(query, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let columns = try #require(board["columns"] as? [[String: Any]]).compactMap { column in column["id"] as? String }
        let edges = try #require((board["tasks"] as? [String: Any])?["edges"] as? [[String: Any]])
        let tasks = try edges.map { edge in
            let node = try #require(edge["node"] as? [String: Any])
            let comments = try #require(node["comments"] as? [[String: Any]]).compactMap { comment in
                comment["body"] as? String
            }
            return (try AddUpdateTaskTests.firstTask(in: try #require(node["id"] as? String)), comments)
        }
        return (columns, Dictionary(uniqueKeysWithValues: tasks))
    }

    // MARK: - Collect

    @Test("Two boards with tasks, comments, and a shared todo column collect into one board with all tasks and one todo column")
    func collectsTasksCommentsAndOneTodoColumn() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        let board = try await Self.board(on: graph)
        await graph.close()
        #expect(board.columns.filter { column in column.hasSuffix(Self.todoSuffix) }.count == 1, "\(board.columns)")
        let expected = try [fixture.first.task, fixture.second.task].map(AddUpdateTaskTests.firstTask(in:))
        #expect(Set(board.tasks.keys) == Set(expected), "\(board.tasks)")
        #expect(expected.allSatisfy { task in board.tasks[task] == [CommentTests.body] }, "\(board.tasks)")
        let merged = try Self.objects("slugMerges", in: report).compactMap { merge in merge["node"] as? String }
        #expect(merged.contains { node in node.hasSuffix(Self.todoSuffix) }, "\(report)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("collectBoards lists the field that two sources set to different values, and the value that won")
    func listsConflictAndWinner() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        let conflict = try #require(
            try Self.objects("conflicts", in: report).first { conflict in
                (conflict["node"] as? String)?.hasSuffix(Self.todoSuffix) == true
                    && conflict["field"] as? String == PropertyName.name
            },
            "\(report)"
        )
        #expect((conflict["winner"] as? String)?.contains(Self.renamedTodo) == true, "\(conflict)")
        #expect((conflict["values"] as? [String])?.count == Self.disagreeingBoardCount, "\(conflict)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("A URI with an old name of a source resolves to the target after collect")
    func oldSourceNameResolvesToTarget() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        let key = try #require(report["target"] as? String)
        let response = try await KanbanGraphTests.execute(#"{ node(id: "\#(fixture.first.task)") { id } }"#, on: graph)
        await graph.close()
        let node = try KanbanGraphTests.object(named: "node", in: response)
        #expect(node["id"] as? String == (try RepairLinksTests.uri(fixture.first.task, withKey: key)), "\(response)")
        let names = try BoardIDTests.boardNode(inRepoAt: fixture.target).oldNames
        #expect(names.contains(fixture.first.id) && names.contains(fixture.second.id), "\(names)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("A dependsOn between the two sources becomes a local ref")
    func dependsOnBetweenSourcesBecomesLocal() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        let checks = try await CheckLinksTests.checks(on: graph)
        await graph.close()
        let key = try #require(report["target"] as? String)
        let link = try #require(checks.checks.first { link in link.field == LinkField.dependsOn.rawValue })
        #expect(link.target == (try RepairLinksTests.uri(fixture.first.task, withKey: key)), "\(checks.response)")
        #expect(link.status == LinkStatus.ok.rawValue, "\(checks.response)")
        let added = try CrossRepoWriteTests.events(ofTask: fixture.second.task, inRepoAt: fixture.target)
            .compactMap { event in event.patch.add[PropertyName.dependsOn] }
            .last
        let local = StoredRef.local(.task(try AddUpdateTaskTests.firstTask(in: fixture.first.task)))
        #expect(added == [local], "\(String(describing: added))")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("collectBoards removes the .kanban folder of each source")
    func removesEachSourceFolder() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        _ = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: fixture.first.folder))
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: fixture.second.folder))
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("dryRun: true reports the slug merges, the conflicts, and the link repairs, and writes and removes nothing")
    func dryRunWritesAndRemovesNothing() async throws {
        let fixture = try await Self.makeFixture()
        let before = try IncompatibleBoardTests.listing(of: fixture.sandbox.root)
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, with: "dryRun: true", on: graph)
        await graph.close()
        #expect(try IncompatibleBoardTests.listing(of: fixture.sandbox.root) == before)
        #expect(report["dryRun"] as? Bool == true)
        #expect(!(try Self.objects("slugMerges", in: report)).isEmpty, "\(report)")
        #expect(!(try Self.objects("conflicts", in: report)).isEmpty, "\(report)")
        let repairs = try Self.objects("repairs", in: report)
        #expect(repairs.contains { repair in repair["field"] as? String == LinkField.dependsOn.rawValue }, "\(report)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("collectBoards makes the target board when the target has no board, with a new board ID")
    func makesTargetBoard() async throws {
        let fixture = try await Self.makeFixture()
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: fixture.target))
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        let id = try BoardIDTests.boardID(inRepoAt: fixture.target)
        #expect(report["target"] as? String == id)
        #expect(![fixture.first.id, fixture.second.id].contains(id))
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("A source of the old Rust kanban stops the call with INCOMPATIBLE_BOARD and writes nothing")
    func rustSourceStopsCall() async throws {
        let fixture = try await Self.makeFixture()
        let rust = try GitSandbox.makeFolder(named: Self.otherName, in: fixture.sandbox.root)
        try IncompatibleBoardTests.writeRustBoard(inRepoAt: rust)
        let before = try IncompatibleBoardTests.listing(of: fixture.sandbox.root)
        let graph = try Self.makeTargetGraph(of: fixture)
        let field = Self.collectField(of: [fixture.first.folder.path, rust.path])
        let response = try await CommentTests.run(field, on: graph)
        await graph.close()
        let error = try #require(try NameRewriteTests.errors(of: response).first)
        #expect(ErrorCoverageTests.code(of: error) == KanbanError.incompatibleBoard(directory: "").code, "\(response)")
        #expect(try IncompatibleBoardTests.listing(of: fixture.sandbox.root) == before)
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("undo does not reverse collectBoards")
    func undoDoesNotReverseCollect() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        _ = try await Self.collect(fixture.sourcePaths, on: graph)
        let response = try await CommentTests.run(CrossRepoUndoTests.undoField, on: graph)
        let board = try await Self.board(on: graph)
        await graph.close()
        let error = try #require(try NameRewriteTests.errors(of: response).first)
        #expect(ErrorCoverageTests.code(of: error) == KanbanError.nothingToUndo.code, "\(response)")
        #expect(board.tasks.count == [fixture.first, fixture.second].count, "\(board.tasks)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    // MARK: - Other boards

    /// Makes a board that is not a source and not the target, whose task depends on the task of the first source.
    ///
    /// - Parameter fixture: The fixture of the test.
    /// - Returns: The board.
    /// - Throws: An error when the folder cannot be made, or when a call fails.
    static func makeOtherBoard(in fixture: Fixture) async throws -> SourceBoard {
        try await makeSourceBoard(
            named: otherName,
            in: fixture.sandbox,
            mintingFrom: FixedULIDSource(at: ReplayTests.date(atStep: otherEngineStep)),
            with: CrossRepoFixture.dependsOnInput(fixture.first.task)
        )
    }

    /// The number of time steps from the ULIDs of the second engine of the fixture to the ULIDs of the engine of the
    /// other board: one step to the third engine (the target), and one more step.
    static let stepsAfterSecondEngine = 2

    /// The time step of the ULIDs of the engine of the other board: after the steps of the three engines of the
    /// fixture.
    static let otherEngineStep = GitGraphFixture.secondEngineStep + stepsAfterSecondEngine

    @Test("collectBoards reports an old-name link of a different board and does not change it with no reach")
    func reportsOtherLinkWithNoReach() async throws {
        let fixture = try await Self.makeFixture()
        let other = try await Self.makeOtherBoard(in: fixture)
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        let links = try Self.objects("otherLinks", in: report)
        #expect(links.map { link in link["target"] as? String } == [fixture.first.task], "\(report)")
        let stored = try CrossRepoWriteTests.events(ofTask: other.task, inRepoAt: other.folder)
            .compactMap { event in event.patch.add[PropertyName.dependsOn] }
        #expect(stored == [[StoredRef.remote(try NodeURI(parsing: fixture.first.task))]], "\(stored)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("collectBoards with reach rewrites an old-name link of a different board to the target")
    func rewritesOtherLinkWithReach() async throws {
        let fixture = try await Self.makeFixture()
        let other = try await Self.makeOtherBoard(in: fixture)
        let graph = try Self.makeTargetGraph(of: fixture)
        let report = try await Self.collect(fixture.sourcePaths, with: "reach: true", on: graph)
        await graph.close()
        let key = try #require(report["target"] as? String)
        let added = try CrossRepoWriteTests.events(ofTask: other.task, inRepoAt: other.folder)
            .compactMap { event in event.patch.add[PropertyName.dependsOn] }
            .last
        let expected = StoredRef.remote(try NodeURI(parsing: try RepairLinksTests.uri(fixture.first.task, withKey: key)))
        #expect(added == [expected], "\(String(describing: added))")
        withExtendedLifetime(fixture.sandbox) {}
    }

    // MARK: - Git repo and crash safety

    /// The path of the subfolder of the git repo that holds a board by mistake, from the top folder of the repo.
    static let subfolderPath = "./Notes"

    @Test("collectBoards in a git repo combines a board in a subfolder into the board at the top folder of the repo")
    func collectsSubfolderBoardIntoRepoTop() async throws {
        let fixture = try await Self.makeFixture()
        let repo = try await fixture.sandbox.makeRepo(named: Self.targetName + "-repo", origin: BoardLocatorTests.appOrigin)
        let subfolder = repo.appending(path: Self.subfolderPath, directoryHint: .isDirectory).standardizedFileURL
        try FileManager.default.moveItem(at: fixture.first.folder, to: subfolder)
        let graph = try GitGraphFixture.makeGraph(at: repo, mintingFrom: GitGraphFixture.thirdEngineIDs)
        let report = try await Self.collect([Self.subfolderPath], on: graph)
        let board = try await Self.board(on: graph)
        await graph.close()
        #expect(report["target"] as? String == (try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)))
        #expect(Set(board.tasks.keys) == [try AddUpdateTaskTests.firstTask(in: fixture.first.task)], "\(board.tasks)")
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: subfolder))
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("The lines of the collect transaction list only the files of its new lines, and a load applies them")
    func collectTransactionListsOnlyItsFiles() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        _ = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        let events = try CrossRepoWriteTests.events(inRepoAt: fixture.target)
        let collected = events.filter { event in event.ops == [MutationName.collectBoards] }
        let merged = events.filter { event in event.ops != [MutationName.collectBoards] }
        let txn = try #require(collected.first?.txn)
        #expect(collected.allSatisfy { event in event.txn == txn })
        #expect(collected.allSatisfy { event in event.files == .named(collected.map(\.patch.node)) }, "\(collected)")
        #expect(!merged.isEmpty)
        #expect(merged.allSatisfy { event in event.txn != txn && event.files != collected[0].files })
        let loaded = try await BoardLoader(reading: EventLog(repositoryAt: fixture.target)).load()
        #expect(Set(collected.map(\.id)).isSubset(of: loaded.events.map(\.id)), "\(loaded.events.map(\.id))")
        #expect(!loaded.heldEvents.contains { event in event.txn == txn }, "\(loaded.heldEvents)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    @Test("A fresh load of the target after collect holds no event and has the task of each source")
    func freshLoadHoldsNoMergedLine() async throws {
        let fixture = try await Self.makeFixture()
        let graph = try Self.makeTargetGraph(of: fixture)
        _ = try await Self.collect(fixture.sourcePaths, on: graph)
        await graph.close()
        let loaded = try await BoardLoader(reading: EventLog(repositoryAt: fixture.target)).load()
        #expect(loaded.heldEvents.isEmpty, "\(loaded.heldEvents)")
        let tasks = try [fixture.first.task, fixture.second.task].map(AddUpdateTaskTests.firstTask(in:))
        #expect(tasks.allSatisfy { task in loaded.graph.isLive(TaskNode.self, for: .task(task)) }, "\(tasks)")
        withExtendedLifetime(fixture.sandbox) {}
    }

    /// The time step of the ULIDs of a target engine whose ids sort before each id of the sources: the time of the
    /// fixture logs, one step before ``KanbanGraphTests/mutationIDs``.
    static let earlyTargetStep = 0

    @Test("The target keeps its board ID, git key, and name when it merges a board line of a source")
    func targetKeepsItsBoardNames() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: Self.firstSourceName, origin: BoardLocatorTests.appOrigin)
        let source = try GitGraphFixture.makeGraph(at: repo, mintingFrom: KanbanGraphTests.mutationIDs)
        _ = try await CrossRepoFixture.addTask(with: "", on: source)
        await source.close()
        let target = try GitSandbox.makeFolder(named: Self.targetName, in: sandbox.root)
        let early = FixedULIDSource(at: ReplayTests.date(atStep: Self.earlyTargetStep))
        let graph = try GitGraphFixture.makeGraph(at: target, mintingFrom: early)
        _ = try await CrossRepoFixture.addTask(with: "", on: graph)
        let before = try BoardIDTests.boardNode(inRepoAt: target)
        _ = try await Self.collect([repo.path], on: graph)
        await graph.close()
        let after = try BoardIDTests.boardNode(inRepoAt: target)
        #expect(after.ids == before.ids, "\(after.ids)")
        #expect(after.gitKey == before.gitKey, "\(String(describing: after.gitKey))")
        #expect(after.name == before.name, "\(after.name)")
        let sourceKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        #expect(after.oldNames.contains(sourceKey), "\(after.oldNames)")
        withExtendedLifetime(sandbox) {}
    }

    @Test("A write that fails keeps each source folder and leaves no event of the call in the target")
    func failedWriteKeepsSources() async throws {
        let fixture = try await Self.makeFixture()
        let sources = try fixture.sourcePaths.map { path in try IncompatibleBoardTests.listing(of: URL(filePath: path)) }
        let graph = try KanbanGraphTests.makeGraph(
            at: fixture.target,
            readingKeyWith: BoardKey.read(fromRepoAt:),
            findingTopWith: BoardKey.worktreeTop(of:),
            mintingFrom: GitGraphFixture.thirdEngineIDs,
            writingLogsWith: FaultingLogWriter(failingAppend: Self.failingAppend)
        )
        await #expect(throws: FaultingLogWriter.fault) {
            try await CommentTests.run(Self.collectField(of: fixture.sourcePaths), on: graph)
        }
        await graph.close()
        let after = try fixture.sourcePaths.map { path in try IncompatibleBoardTests.listing(of: URL(filePath: path)) }
        #expect(after == sources)
        #expect(try CrossRepoWriteTests.events(inRepoAt: fixture.target).isEmpty)
        withExtendedLifetime(fixture.sandbox) {}
    }

    /// The number of the append that fails in ``failedWriteKeepsSources()``: an append after the first, so that the
    /// commit must take back a file that it wrote.
    static let failingAppend = 2
}
