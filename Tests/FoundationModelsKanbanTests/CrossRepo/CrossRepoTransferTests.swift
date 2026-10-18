import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the move and the copy of a task to a different board (divergence.md Q21, E6, G8): `moveTask` with a
/// `board` field, and `copyTask`. The new task keeps its refs to the old board as full URIs, each missing tag is made
/// on the target board, a move tombstones the old task and adds a line with the new URI to its body, and one `undo`
/// reverses both boards.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/`
/// directory of this repo.
@Suite("Cross-repo: move and copy a task to a different board", .watcherBudget)
struct CrossRepoTransferTests {
    /// The body of a task that a test moves or copies.
    static let keptBody = "Keep this line."

    /// The `body` field of an `addTask` input with ``keptBody``.
    static let keptBodyInput = #"body: "\#(keptBody)""#

    /// The slug of a default column after the first column.
    static let doingSlug = "doing"

    /// The slug of the first default column.
    static let todoSlug = "todo"

    /// The name of an edge tag of the moved or copied task. The target board does not have this tag before the call.
    static let edgeTagName = "frontend"

    /// The name of a tag that only a body marker of the moved or copied task names.
    static let markerTagName = "parser"

    /// The selection of the name of each tag of a board.
    static let tagNamesSelection = "tags { name }"

    /// The mutations that write a task to a board that the `board` field names.
    static let transferOperations = [MutationName.moveTask, MutationName.copyTask]

    /// The `board` field that names a board that no scan finds.
    static let missingBoard = CrossRepoWriteTests.boardField(CrossRepoReadTests.missingKey)

    /// The `extensions.code` of a node or a board that a ref does not name.
    static let notFoundCode = "NOT_FOUND"

    /// The name of the assignee of a moved or copied task. Its slug is not ``AddUpdateTaskTests/alice``, the slug of
    /// the actor, so a filter can name the actor by its slug or by the slug of its name.
    static let assigneeName = "Alice Smith"

    /// The slug of ``assigneeName``.
    static let assigneeNameSlug = "alice-smith"

    /// The selection of the id and the name of each assignee of a task.
    static let assigneesSelection = "assignees { id name }"

    /// The selection of the body of each comment of a task.
    static let commentsSelection = "{ comments { body } }"

    /// The selection of the tombstone time and the task of a comment.
    static let commentTaskSelection = "{ deleted task { id } }"

    // MARK: - Helpers

    /// Runs a mutation field on a fixture board whose related boards can load but are not loaded yet, so that each
    /// board ref of the field waits for a load. No engine runs the load, so the response is the response of that run.
    ///
    /// - Parameter field: The mutation field, with its selection.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the context cannot be made, or the response cannot be encoded.
    static func respondBeforeLoad(to field: String) async throws -> String {
        try await PublicSchema().respond(
            to: AddUpdateTaskTests.mutation(of: field),
            context: GraphQLEngineTests.makeContext(reading: .loadable)
        )
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
        try await id(givenBy: CommentTests.nodeField(operation, naming: task, with: input), named: operation, on: graph)
    }

    /// Runs a mutation field with an `id` selection, and expects that the response has no error.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with an `id` selection.
    ///   - name: The name of the mutation, for example `addComment`.
    ///   - graph: The engine of the current repo.
    /// - Returns: The full URI of the node that the field gives.
    /// - Throws: An error when the response has no id for the field.
    static func id(givenBy field: String, named name: String, on graph: KanbanGraph) async throws -> String {
        let response = try await CommentTests.run(field, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        return try CrossRepoUndoTests.id(of: name, in: KanbanGraphTests.data(of: response))
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
        try await node(task, ofType: GraphQLTypeName.task, selecting: selection, on: graph)
    }

    /// Reads the fields of a node of any loaded board with `Query.node`.
    ///
    /// - Parameters:
    ///   - node: The full URI of the node.
    ///   - type: The GraphQL name of the type of the node, for example `Comment`.
    ///   - selection: The selection of the fields of the type, for example `{ body }`.
    ///   - graph: The engine of the current repo.
    /// - Returns: The node object of the response.
    /// - Throws: An error when the response has no node.
    static func node(
        _ node: String,
        ofType type: String,
        selecting selection: String,
        on graph: KanbanGraph
    ) async throws -> [String: Any] {
        let query = #"{ node(id: "\#(node)") { ... on \#(type) \#(selection) } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        return try KanbanGraphTests.object(named: "node", in: response)
    }

    /// Reads the tag names of the related board.
    ///
    /// - Parameter graph: The engine of the current repo.
    /// - Returns: The names of the live tags.
    /// - Throws: An error when the response has no board.
    static func libTagNames(on graph: KanbanGraph) async throws -> [String] {
        let query = #"{ board(id: "\#(try CrossRepoWriteTests.libKey())") { \#(tagNamesSelection) } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        let board = try KanbanGraphTests.object(named: "board", in: response)
        return try names(in: board["tags"])
    }

    /// Gives the names of a list of tags of a response.
    ///
    /// - Parameter tags: The list value of the response, with a `name` selection.
    /// - Returns: The names.
    /// - Throws: An error when the value is not a list of objects.
    static func names(in tags: Any?) throws -> [String] {
        try texts(of: "name", in: tags)
    }

    /// Gives the text value of one field of each object of a list of a response.
    ///
    /// - Parameters:
    ///   - field: The name of the field of each object, for example `id` or `name`.
    ///   - list: The list value of the response.
    /// - Returns: The text values. An object with no text value for the field gives no value.
    /// - Throws: An error when the value is not a list of objects.
    static func texts(of field: String, in list: Any?) throws -> [String] {
        try #require(list as? [[String: Any]]).compactMap { object in object[field] as? String }
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

    /// Gives the ids of the objects of one list field of a task object of a response, for example `dependsOn` or
    /// `assignees`.
    ///
    /// - Parameters:
    ///   - task: The task object of the response, with an `id` selection in the list field.
    ///   - key: The name of the list field.
    /// - Returns: The ids.
    /// - Throws: An error when the task has no list of objects for the key.
    static func ids(of task: [String: Any], under key: String) throws -> [String] {
        try texts(of: "id", in: task[key])
    }

    /// Two repos side by side, and a task of the related repo that a move or a copy wrote there from the current repo.
    struct AssignedTransfer {
        /// The repos.
        let repos: CrossRepoFixture.SideBySide

        /// The full URI of the task that the move or the copy wrote on the related board.
        let written: String

        /// The full URI of the assignee on the current board: the ref that the written task stores.
        let actor: String
    }

    /// Moves or copies a task with one assignee to the related repo. The assignee is an actor of the current board,
    /// with the slug ``AddUpdateTaskTests/alice`` and the name ``assigneeName``. The engine of the setup is closed when
    /// the function returns.
    ///
    /// - Parameter operation: `moveTask` or `copyTask`.
    /// - Returns: The repos, the written task, and the URI of the assignee.
    /// - Throws: An error when a git command fails, or when a call fails.
    static func makeAssignedTransfer(_ operation: String) async throws -> AssignedTransfer {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await makeAssignedOldTask(named: assigneeName, on: app)
        let written = try await transfer(operation, old, with: try libBoard(), on: app)
        await app.close()
        let actor = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .actor(slug: AddUpdateTaskTests.alice))
        return AssignedTransfer(repos: repos, written: written, actor: actor.description)
    }

    /// Adds an actor with the slug ``AddUpdateTaskTests/alice`` to the current board, and a task with that actor as
    /// its one assignee.
    ///
    /// - Parameters:
    ///   - name: The name of the actor.
    ///   - app: The engine of the current repo.
    /// - Returns: The full URI of the task.
    /// - Throws: An error when a call fails.
    static func makeAssignedOldTask(named name: String, on app: KanbanGraph) async throws -> String {
        let actorInput = #"id: "\#(AddUpdateTaskTests.alice)", name: "\#(name)""#
        _ = try await CommentTests.run("addActor(input: { \(actorInput) }) { id }", on: app)
        let assignees = "assignees: " + AddUpdateTaskTests.list(of: [AddUpdateTaskTests.alice])
        return try await CrossRepoFixture.addTask(with: assignees, on: app)
    }

    /// Opens an engine on the related repo, so that the related board is the current board of each call.
    ///
    /// - Parameter repos: The repos.
    /// - Returns: The engine. The caller closes it.
    /// - Throws: An error when the engine cannot be made.
    static func makeLibGraph(in repos: CrossRepoFixture.SideBySide) throws -> KanbanGraph {
        try GitGraphFixture.makeGraph(at: repos.lib, mintingFrom: GitGraphFixture.secondEngineIDs)
    }

    /// Gives the query of the tasks of the current board that a filter selects, with the id and the assignees of each.
    ///
    /// - Parameter filter: The filter.
    /// - Returns: The query.
    static func filteredTasksQuery(_ filter: String) -> String {
        #"{ board { tasks(filter: "\#(filter)") { edges { node { id \#(assigneesSelection) } } } } }"#
    }

    /// Gives the tasks of a `filteredTasksQuery(_:)` response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The task objects, in board order.
    /// - Throws: An error when the response has no task list.
    static func filteredTasks(in response: String) throws -> [[String: Any]] {
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let connection = try #require(board["tasks"] as? [String: Any], "\(response)")
        let edges = try #require(connection["edges"] as? [[String: Any]], "\(response)")
        return try edges.map { edge in try #require(edge["node"] as? [String: Any]) }
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

    /// divergence.md Q21, option A: a move does not copy the comments. Each comment stays live, with its edge to the
    /// old task (the tombstone). `Query.node` reads the comment by its URI.
    @Test("A move keeps each comment on the old task, and the new task has no comments")
    func moveKeepsCommentsOnOldTask() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let add = CommentTests.addComment(to: old)
        let comment = try await Self.id(givenBy: add, named: MutationName.addComment, on: app)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: try Self.libBoard(), on: app)
        let commentNode = try await Self.node(
            comment,
            ofType: GraphQLTypeName.comment,
            selecting: Self.commentTaskSelection,
            on: app
        )
        let task = try await Self.task(moved, selecting: Self.commentsSelection, on: app)
        await app.close()
        #expect(commentNode["deleted"] is NSNull)
        #expect(try #require(commentNode["task"] as? [String: Any])["id"] as? String == old)
        #expect(try Self.texts(of: "body", in: task["comments"]).isEmpty)
    }

    @Test("moveTask with a board that holds the task moves the task in its board, with no tombstone")
    func moveToSameBoardMovesInBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let board = CrossRepoWriteTests.boardField(try CrossRepoWriteTests.appKey())
        let input = board + ", " + TaskOperationTests.moveInput(to: Self.doingSlug)
        let moved = try await Self.transfer(MutationName.moveTask, old, with: input, on: app)
        let task = try await Self.task(old, selecting: "{ deleted column { id } }", on: app)
        await app.close()
        #expect(moved == old)
        #expect(task["deleted"] is NSNull)
        let expected = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .column(slug: Self.doingSlug))
        #expect(try Self.columnID(of: task) == expected.description)
    }

    @Test(
        "The dependencies of a moved or copied task on the old board still resolve, as full URIs",
        arguments: transferOperations
    )
    func dependenciesResolveAfterTransfer(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoFixture.addTask(with: "", on: app)
        let old = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let written = try await Self.transfer(operation, old, with: try Self.libBoard(), on: app)
        let selection = "{ ready unresolvedDependsOn dependsOn { id } }"
        let task = try await Self.task(written, selecting: selection, on: app)
        await app.close()
        #expect(try Self.ids(of: task, under: PropertyName.dependsOn) == [target])
        #expect((task["unresolvedDependsOn"] as? [String])?.isEmpty == true)
        #expect(task["ready"] as? Bool == false)
    }

    @Test(
        "A move or a copy to the board of a dependency stores that dependency as a local ref, and it still resolves",
        arguments: transferOperations
    )
    func dependencyOnTargetBoardBecomesLocal(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoFixture.addTask(with: try Self.libBoard(), on: app)
        let old = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let written = try await Self.transfer(operation, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(written, selecting: "{ dependsOn { id } }", on: app)
        await app.close()
        let added = try #require(try CrossRepoWriteTests.events(ofTask: written, inRepoAt: repos.lib).first).patch.add
        let local = LocalRef.task(try AddUpdateTaskTests.firstTask(in: target))
        #expect(added[PropertyName.dependsOn] == [.local(local)])
        #expect(try Self.ids(of: task, under: PropertyName.dependsOn) == [target])
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

    @Test(
        "A move or a copy to a different board puts the new task in the column of that board that the input names",
        arguments: transferOperations
    )
    func transferGoesToNamedColumn(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let input = try Self.libBoard() + ", " + TaskOperationTests.moveInput(to: Self.doingSlug)
        let written = try await Self.transfer(operation, old, with: input, on: app)
        let task = try await Self.task(written, selecting: "{ column { id } }", on: app)
        await app.close()
        let expected = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .column(slug: Self.doingSlug))
        #expect(try Self.columnID(of: task) == expected.description)
    }

    @Test("copyTask with no board copies the task in its own board")
    func copyWithNoBoardCopiesInBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: app)
        let input = TaskOperationTests.moveInput(to: Self.todoSlug)
        let copy = try await Self.transfer(MutationName.copyTask, old, with: input, on: app)
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
        let copy = try CrossRepoUndoTests.id(of: MutationName.copyTask, in: KanbanGraphTests.data(of: response))
        #expect(try Self.boardKey(of: copy) == CrossRepoWriteTests.libKey())
    }

    // MARK: - Tags and assignees

    @Test("A move or a copy makes each edge tag that the target board does not have", arguments: transferOperations)
    func transferMakesMissingEdgeTag(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tags = "tags: " + AddUpdateTaskTests.list(of: [Self.edgeTagName])
        let old = try await CrossRepoFixture.addTask(with: tags, on: app)
        let written = try await Self.transfer(operation, old, with: try Self.libBoard(), on: app)
        let task = try await Self.task(written, selecting: "{ \(Self.tagNamesSelection) }", on: app)
        let boardTags = try await Self.libTagNames(on: app)
        await app.close()
        #expect(boardTags.contains(Self.edgeTagName))
        #expect(try Self.names(in: task["tags"]) == [Self.edgeTagName])
    }

    @Test(
        "A move or a copy makes each tag of a body marker that the target board does not have",
        arguments: transferOperations
    )
    func transferMakesMissingMarkerTag(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: #"body: "Fix the #\#(Self.markerTagName) bug.""#, on: app)
        _ = try await Self.transfer(operation, old, with: try Self.libBoard(), on: app)
        let boardTags = try await Self.libTagNames(on: app)
        await app.close()
        #expect(boardTags.contains(Self.markerTagName))
    }

    @Test(
        "A move or a copy stores each assignee of the old board as the full URI of the actor on the old board",
        arguments: transferOperations
    )
    func transferStoresAssigneeAsOldBoardURI(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await Self.makeAssignedOldTask(named: AddUpdateTaskTests.alice, on: app)
        let written = try await Self.transfer(operation, old, with: try Self.libBoard(), on: app)
        await app.close()
        let added = try #require(try CrossRepoWriteTests.events(ofTask: written, inRepoAt: repos.lib).first).patch.add
        let actor = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .actor(slug: AddUpdateTaskTests.alice))
        #expect(added[PropertyName.assignees] == [.remote(actor)])
    }

    @Test(
        "After a move or a copy, Task.assignees of the new task gives the actor of the old board",
        arguments: transferOperations
    )
    func assigneesGiveActorOfOldBoard(operation: String) async throws {
        let transfer = try await Self.makeAssignedTransfer(operation)
        let lib = try Self.makeLibGraph(in: transfer.repos)
        let task = try await Self.task(transfer.written, selecting: "{ \(Self.assigneesSelection) }", on: lib)
        await lib.close()
        #expect(try Self.ids(of: task, under: PropertyName.assignees) == [transfer.actor])
        #expect(try Self.names(in: task["assignees"]) == [Self.assigneeName])
    }

    @Test(
        "After a move or a copy, the @ filter with the slug of the actor or of its name finds the new task",
        arguments: transferOperations,
        [AddUpdateTaskTests.alice, assigneeNameSlug]
    )
    func assigneeFilterFindsTransferredTask(operation: String, actor: String) async throws {
        let transfer = try await Self.makeAssignedTransfer(operation)
        let lib = try Self.makeLibGraph(in: transfer.repos)
        let response = try await KanbanGraphTests.execute(Self.filteredTasksQuery("@" + actor), on: lib)
        await lib.close()
        let tasks = try Self.filteredTasks(in: response)
        #expect(try Self.texts(of: "id", in: tasks) == [transfer.written])
    }

    @Test("After a move, the @ filter with the full URI of the actor on the old board finds the new task")
    func assigneeURIFilterFindsMovedTask() async throws {
        let transfer = try await Self.makeAssignedTransfer(MutationName.moveTask)
        let lib = try Self.makeLibGraph(in: transfer.repos)
        let response = try await KanbanGraphTests.execute(Self.filteredTasksQuery("@" + transfer.actor), on: lib)
        await lib.close()
        let tasks = try Self.filteredTasks(in: response)
        #expect(try Self.texts(of: "id", in: tasks) == [transfer.written])
    }

    /// The `@` filter finds the task by the slug in the URI, `Task.assignees` leaves the actor out, and the response
    /// warns about the board.
    @Test("When the old board cannot be read, the @ filter and Task.assignees keep working, with a warning")
    func unreadableOldBoardKeepsAssigneeReadsWorking() async throws {
        let transfer = try await Self.makeAssignedTransfer(MutationName.moveTask)
        try UnreadableRelatedBoardTests.Breakage.brokenLog.apply(toTask: transfer.written, inRepoAt: transfer.repos.app)
        let lib = try Self.makeLibGraph(in: transfer.repos)
        let response = try await KanbanGraphTests.execute(
            Self.filteredTasksQuery("@" + AddUpdateTaskTests.alice),
            on: lib
        )
        await lib.close()
        let tasks = try Self.filteredTasks(in: response)
        #expect(try Self.texts(of: "id", in: tasks) == [transfer.written])
        #expect(try tasks.map { task in try Self.ids(of: task, under: PropertyName.assignees) } == [[]])
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [UnreadableRelatedBoardTests.warningCode])
        let message = try #require(warnings.first?.message)
        #expect(message.contains(try CrossRepoWriteTests.appKey()), "\(message)")
    }

    // MARK: - Errors

    @Test(
        "A move or a copy to a board that the scan cannot find gives NOT_FOUND for the board",
        arguments: transferOperations
    )
    func missingTargetBoardGivesNotFound(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: first)
        await first.close()
        let field = CommentTests.nodeField(operation, naming: old, with: Self.missingBoard)
        let expected = KanbanError.boardNotFound(
            reference: CrossRepoReadTests.missingKey,
            searchRoots: [repos.sandbox.root.path]
        )
        try await CrossRepoWriteTests.expectFailure(
            of: field,
            named: operation,
            in: repos,
            giving: expected,
            coded: Self.notFoundCode
        )
    }

    @Test("A move or a copy of a task that no board has gives NOT_FOUND for the task", arguments: transferOperations)
    func missingTaskGivesNotFound(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let missing = NodeURI(boardKey: try CrossRepoWriteTests.appKey(), ref: .task(ULID())).description
        let field = CommentTests.nodeField(operation, naming: missing, with: try Self.libBoard())
        try await CrossRepoWriteTests.expectFailure(
            of: field,
            named: operation,
            in: repos,
            giving: .notFound(type: .task, reference: missing),
            coded: Self.notFoundCode
        )
    }

    @Test(
        "A move or a copy to a board that the engine did not load gives NOT_FOUND for the board, not a null",
        arguments: transferOperations
    )
    func unloadedTargetBoardGivesNotFound(operation: String) async throws {
        let field = CommentTests.nodeField(
            operation,
            naming: AddUpdateTaskTests.sigilRef(of: ULID()),
            with: Self.missingBoard
        )
        let response = try await Self.respondBeforeLoad(to: field)
        let expected = KanbanError.boardNotFound(reference: CrossRepoReadTests.missingKey, searchRoots: [])
        try ErrorCoverageTests.expectFailure(of: operation, in: response, giving: expected, coded: Self.notFoundCode)
    }

    @Test(
        "A move or a copy of a task of a board that the engine did not load gives NOT_FOUND for the task, not a null",
        arguments: transferOperations,
        ["", missingBoard]
    )
    func unloadedTaskBoardGivesNotFound(operation: String, board: String) async throws {
        let missing = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        let response = try await Self.respondBeforeLoad(
            to: CommentTests.nodeField(operation, naming: missing, with: board)
        )
        try ErrorCoverageTests.expectFailure(
            of: operation,
            in: response,
            giving: .notFound(type: .task, reference: missing),
            coded: Self.notFoundCode
        )
    }

    // MARK: - Incompatible board

    @Test(
        "A move or a copy to a related Rust board gives INCOMPATIBLE_BOARD and writes nothing",
        arguments: transferOperations
    )
    func transferToRustBoardWritesNothing(operation: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let old = try await CrossRepoFixture.addTask(with: "", on: first)
        await first.close()
        try IncompatibleBoardTests.RustOnlyPath.file(UnreadableRelatedBoardTests.rustLogName).make(inRepoAt: repos.lib)
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.app)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let response = try await CommentTests.run(
            CommentTests.nodeField(operation, naming: old, with: try Self.libBoard()),
            on: app
        )
        await app.close()
        #expect(response == (try IncompatibleBoardTests.libIncompatibleResponse(in: repos)))
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.app) == before)
    }
}
