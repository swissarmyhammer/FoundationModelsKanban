import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the move and the copy of a task to a different board (divergence.md Q21, E6, G8): `moveTask` with a
/// `board` field, and `copyTask`. The new task keeps its refs to the old board as full URIs, each missing tag is made
/// on the target board, a move tombstones the old task and adds a line with the new URI to its body, and one `undo`
/// reverses both boards.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/`
/// directory of this repo.
@Suite("Cross-repo: move and copy a task to a different board", .watcherBudget, .timeLimit(.minutes(1)))
struct CrossRepoTransferTests {
    /// The body of a task that a test moves or copies.
    static let keptBody = "Keep this line."

    /// The `body` field of an `addTask` input with ``keptBody``.
    static let keptBodyInput = #"body: "\#(keptBody)""#

    /// The slug of a default column after the first column.
    static let doingSlug = "doing"

    /// The slug of the first default column.
    static let todoSlug = "todo"

    /// The name of an edge tag of the moved task. The target board does not have this tag before the move.
    static let edgeTagName = "frontend"

    /// The name of a tag that only a body marker of the moved task names.
    static let markerTagName = "parser"

    /// The selection of the name of each tag of a board.
    static let tagNamesSelection = "tags { name }"

    // MARK: - Helpers

    /// Gives the mutation field that moves or copies a task.
    ///
    /// - Parameters:
    ///   - operation: `moveTask` or `copyTask`.
    ///   - task: The full URI of the task.
    ///   - input: The other fields of the input, for example a `board` field.
    /// - Returns: The field, with the `id` selection.
    static func field(_ operation: String, of task: String, with input: String) -> String {
        #"\#(operation)(input: { id: "\#(task)", \#(input) }) { id }"#
    }

    /// Gives the `column` field of an input.
    ///
    /// - Parameter slug: The slug of the column.
    /// - Returns: The `input` field.
    static func columnField(_ slug: String) -> String {
        #"column: "\#(slug)""#
    }

    /// Moves or copies a task with one call, and expects that the response has no error.
    ///
    /// - Parameters:
    ///   - operation: `moveTask` or `copyTask`.
    ///   - task: The full URI of the task.
    ///   - input: The other fields of the input, for example a `board` field.
    ///   - graph: The engine of the current repo.
    /// - Returns: The full URI of the task that the field gives.
    /// - Throws: An error when the response has no id for the field.
    static func transfer(
        _ operation: String,
        _ task: String,
        with input: String,
        on graph: KanbanGraph
    ) async throws -> String {
        let response = try await CommentTests.run(field(operation, of: task, with: input), on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        return try CrossRepoUndoTests.id(of: operation, in: NameRewriteTests.data(of: response))
    }

    /// The `board` field that names the related repo.
    ///
    /// - Returns: The `input` field.
    /// - Throws: An error when the remote URL of the related repo is not valid.
    static func libBoard() throws -> String {
        CrossRepoWriteTests.boardField(try CrossRepoWriteTests.libKey())
    }

    /// Reads the fields of a task of any loaded board with `Query.node`.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - selection: The selection of the task fields, for example `{ title }`.
    ///   - graph: The engine of the current repo.
    /// - Returns: The task object of the response.
    /// - Throws: An error when the response has no task.
    static func task(_ task: String, selecting selection: String, on graph: KanbanGraph) async throws -> [String: Any] {
        let query = #"{ node(id: "\#(task)") { ... on Task \#(selection) } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        return try #require(NameRewriteTests.data(of: response)["node"] as? [String: Any], "\(response)")
    }

    /// Reads the tag names of the related board.
    ///
    /// - Parameter graph: The engine of the current repo.
    /// - Returns: The names of the live tags.
    /// - Throws: An error when the response has no board.
    static func libTagNames(on graph: KanbanGraph) async throws -> [String] {
        let query = #"{ board(id: "\#(try CrossRepoWriteTests.libKey())") { \#(tagNamesSelection) } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        let board = try #require(NameRewriteTests.data(of: response)["board"] as? [String: Any], "\(response)")
        return try names(in: board["tags"])
    }

    /// Gives the names of a list of tags of a response.
    ///
    /// - Parameter tags: The list value of the response, with a `name` selection.
    /// - Returns: The names.
    /// - Throws: An error when the value is not a list of objects.
    static func names(in tags: Any?) throws -> [String] {
        try #require(tags as? [[String: Any]]).compactMap { tag in tag["name"] as? String }
    }

    /// Gives the key of the board of a full URI.
    ///
    /// - Parameter uri: The full URI of a node.
    /// - Returns: The board key.
    /// - Throws: An error when the text is not a node URI.
    static func boardKey(of uri: String) throws -> String {
        try NodeURI(parsing: uri).boardKey
    }

    /// Gives the id of the column of a task object of a response.
    ///
    /// - Parameter task: The task object of the response, with a `column { id }` selection.
    /// - Returns: The full URI of the column.
    /// - Throws: An error when the task has no column.
    static func columnID(of task: [String: Any]) throws -> String? {
        try #require(task["column"] as? [String: Any])["id"] as? String
    }

    /// Gives the ids of the tasks of a `dependsOn` list of a response.
    ///
    /// - Parameter task: The task object of the response, with a `dependsOn { id }` selection.
    /// - Returns: The ids.
    /// - Throws: An error when the task has no `dependsOn` list.
    static func dependencyIDs(of task: [String: Any]) throws -> [String] {
        try #require(task["dependsOn"] as? [[String: Any]]).compactMap { target in target["id"] as? String }
    }

    // MARK: - Move

    @Test("moveTask with board makes the task on the other board and tombstones the old task, in one transaction")
    func moveMakesTaskOnOtherBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(moved, selecting: "{ title deleted }", on: app)
        let oldTask = try await Self.task(old, selecting: "{ deleted }", on: app)
        await app.close()
        #expect(try Self.boardKey(of: moved) == CrossRepoWriteTests.libKey())
        #expect(task["title"] as? String == AddUpdateTaskTests.title)
        #expect(task["deleted"] is NSNull)
        #expect(oldTask["deleted"] is String)
        let transactions = [
            try CrossRepoUndoTests.lastEvent(ofTask: old, inRepoAt: repos.app).txn,
            try CrossRepoUndoTests.lastEvent(ofTask: moved, inRepoAt: repos.lib).txn,
        ]
        #expect(Set(transactions).count == 1)
    }

    @Test("A move adds a line with the URI of the new task to the body of the old task")
    func moveAddsPointerLine() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: Self.keptBodyInput, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let oldTask = try await Self.task(old, selecting: "{ body }", on: app)
        await app.close()
        let body = try #require(oldTask["body"] as? String)
        #expect(body.hasPrefix(Self.keptBody))
        #expect(body.contains(moved))
    }

    @Test("moveTask with a board that holds the task moves the task in its board, with no tombstone")
    func moveToSameBoardMovesInBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let board = CrossRepoWriteTests.boardField(try CrossRepoWriteTests.appKey())
        let input = board + ", " + Self.columnField(Self.doingSlug)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: input, on: app)
        let task = try await Self.task(old, selecting: "{ deleted column { id } }", on: app)
        await app.close()
        #expect(moved == old)
        #expect(task["deleted"] is NSNull)
        let expected = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .column(slug: Self.doingSlug))
        #expect(try Self.columnID(of: task) == expected.description)
    }

    @Test("The dependencies of a moved task on the old board still resolve, as full URIs")
    func dependenciesResolveAfterMove() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoFixture.addTask(with: "", on: app)
        let old = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let selection = "{ ready unresolvedDependsOn dependsOn { id } }"
        let task = try await Self.task(moved, selecting: selection, on: app)
        await app.close()
        #expect(try Self.dependencyIDs(of: task) == [target])
        #expect((task["unresolvedDependsOn"] as? [String])?.isEmpty == true)
        #expect(task["ready"] as? Bool == false)
    }

    @Test("A task on the old board that depended on the moved task ignores the tombstone, and is ready")
    func dependentIgnoresTombstone() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let dependent = try await CrossRepoFixture.addTask(dependingOn: old, on: app)
        _ = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(dependent, selecting: "{ ready }", on: app)
        await app.close()
        #expect(task["ready"] as? Bool == true)
    }

    @Test("One undo of a move makes the old task live again and tombstones the new task")
    func undoOfMoveRestoresBothBoards() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: Self.keptBodyInput, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: app)
        let oldTask = try await Self.task(old, selecting: "{ deleted body }", on: app)
        let task = try await Self.task(moved, selecting: "{ deleted }", on: app)
        await app.close()
        #expect(oldTask["deleted"] is NSNull)
        #expect(oldTask["body"] as? String == Self.keptBody)
        #expect(task["deleted"] is String)
    }

    // MARK: - Copy

    @Test("copyTask makes a copy on the other board, and keeps the old task live")
    func copyKeepsOldTask() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: Self.keptBodyInput, on: app)
        let copy = try await Self.transfer(MutationName.copyTask, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(copy, selecting: "{ title body }", on: app)
        let oldTask = try await Self.task(old, selecting: "{ deleted body }", on: app)
        await app.close()
        #expect(try Self.boardKey(of: copy) == CrossRepoWriteTests.libKey())
        #expect(task["title"] as? String == AddUpdateTaskTests.title)
        #expect(task["body"] as? String == Self.keptBody)
        #expect(oldTask["deleted"] is NSNull)
        #expect(oldTask["body"] as? String == Self.keptBody)
    }

    @Test("copyTask puts the copy in the column that the input names")
    func copyGoesToNamedColumn() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let input = try Self.libBoard() + ", " + Self.columnField(Self.doingSlug)
        let copy = try await Self.transfer(MutationName.copyTask, old, with: input, on: app)
        let task = try await Self.task(copy, selecting: "{ column { id } }", on: app)
        await app.close()
        let expected = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .column(slug: Self.doingSlug))
        #expect(try Self.columnID(of: task) == expected.description)
    }

    @Test("copyTask with no board copies the task in its own board")
    func copyWithNoBoardCopiesInBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let copy = try await Self.transfer(MutationName.copyTask, old, with: Self.columnField(Self.todoSlug), on: app)
        let task = try await Self.task(copy, selecting: "{ title }", on: app)
        await app.close()
        #expect(copy != old)
        #expect(try Self.boardKey(of: copy) == CrossRepoWriteTests.appKey())
        #expect(task["title"] as? String == AddUpdateTaskTests.title)
    }

    @Test("One undo of a copy tombstones the copy, and keeps the old task live")
    func undoOfCopyRemovesCopy() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let copy = try await Self.transfer(MutationName.copyTask, old, with: try Self.libBoard(), on: app)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: app)
        let task = try await Self.task(copy, selecting: "{ deleted }", on: app)
        let oldTask = try await Self.task(old, selecting: "{ deleted }", on: app)
        await app.close()
        #expect(task["deleted"] is String)
        #expect(oldTask["deleted"] is NSNull)
    }

    @Test("copyTask accepts the forgiving names: task for id, toBoard for board, and toColumn for column")
    func copyAcceptsAliases() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let board = #"toBoard: "\#(try CrossRepoWriteTests.libKey())""#
        let input = #"task: "\#(old)", \#(board), toColumn: "\#(Self.doingSlug)""#
        let response = try await CommentTests.run("\(MutationName.copyTask)(input: { \(input) }) { id }", on: app)
        await app.close()
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        let copy = try CrossRepoUndoTests.id(of: MutationName.copyTask, in: NameRewriteTests.data(of: response))
        #expect(try Self.boardKey(of: copy) == CrossRepoWriteTests.libKey())
    }

    // MARK: - Tags and assignees

    @Test("A move makes each edge tag that the target board does not have")
    func moveMakesMissingEdgeTag() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tags = "tags: " + AddUpdateTaskTests.list(of: [Self.edgeTagName])
        let old = try await CrossRepoFixture.addTask(with: tags, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(moved, selecting: "{ \(Self.tagNamesSelection) }", on: app)
        let boardTags = try await Self.libTagNames(on: app)
        await app.close()
        #expect(boardTags.contains(Self.edgeTagName))
        #expect(try Self.names(in: task["tags"]) == [Self.edgeTagName])
    }

    @Test("A move makes each tag of a body marker that the target board does not have")
    func moveMakesMissingMarkerTag() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: #"body: "Fix the #\#(Self.markerTagName) bug.""#, on: app)
        _ = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let boardTags = try await Self.libTagNames(on: app)
        await app.close()
        #expect(boardTags.contains(Self.markerTagName))
    }

    @Test("A move stores each assignee of the old board as the full URI of the actor on the old board")
    func moveStoresAssigneeAsOldBoardURI() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await CommentTests.run(#"addActor(input: { name: "\#(AddUpdateTaskTests.alice)" }) { id }"#, on: app)
        let assignees = "assignees: " + AddUpdateTaskTests.list(of: [AddUpdateTaskTests.alice])
        let old = try await CrossRepoFixture.addTask(with: assignees, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        await app.close()
        let added = try #require(try CrossRepoWriteTests.events(ofTask: moved, inRepoAt: repos.lib).first).patch.add
        let actor = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .actor(slug: AddUpdateTaskTests.alice))
        #expect(added[PropertyName.assignees] == [.remote(actor)])
    }

    // MARK: - Incompatible board

    @Test("A move to a related Rust board gives INCOMPATIBLE_BOARD and writes nothing")
    func moveToRustBoardWritesNothing() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: first)
        await first.close()
        try IncompatibleBoardTests.RustOnlyPath.file(UnreadableRelatedBoardTests.rustLogName).make(inRepoAt: repos.lib)
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.app)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let response = try await CommentTests.run(
            Self.field(MutationName.moveTask, of: old, with: try Self.libBoard()),
            on: app
        )
        await app.close()
        #expect(response == (try IncompatibleBoardTests.libIncompatibleResponse(in: repos)))
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.app) == before)
    }
}
