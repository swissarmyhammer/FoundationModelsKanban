import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the change cursor of the `kanban` endpoint (KANBAN-7; EXTRAS-9 rev 2, rule 9): the root query `cursor`, the
/// `cursor` of each `Change`, and `changes(after:)`, which replays the changes of the change log of the board after a
/// cursor and then gives the live changes.
///
/// Each test reads the events of a subscription with the time limit of ``FolderEventWait``, and closes each engine
/// and each host that it makes.
@Suite("Change cursor: cursor, changes(after:), and RESYNC_REQUIRED", .watcherBudget)
struct ChangeCursorTests {
    /// The `extensions.code` of a subscription that cannot resume after its cursor.
    static let resyncCode = "RESYNC_REQUIRED"

    /// The selection of each event of most tests: the cursor and the transaction.
    static let cursorSelection = "{ cursor txn }"

    /// The selection of each event of the test of the id lists: the three lists, and the id and the kind of each
    /// update.
    static let idListSelection = "{ added changed removed updates { id kind } }"

    /// The number of changes that the change log of the host of the overflow test keeps.
    static let smallCapacity = 1

    /// The name of the session actor of the first session of a host test.
    static let firstActor = "Agent A"

    /// The name of the session actor of the second session of a host test.
    static let secondActor = "Agent B"

    // MARK: - Helpers

    /// Reads the root `cursor` of an engine.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The cursor.
    /// - Throws: An error when the response has no cursor.
    static func cursor(on graph: KanbanGraph) async throws -> String {
        let response = try await KanbanGraphTests.execute("{ cursor }", on: graph)
        return try #require(KanbanGraphTests.data(of: response)["cursor"] as? String, "\(response)")
    }

    /// Makes a `changes` subscription document.
    ///
    /// - Parameters:
    ///   - cursor: The cursor to resume after, or `nil` for the live changes only.
    ///   - arguments: The other arguments of the field, for example `filter: "~task"`, or `""` for none.
    ///   - selection: The selection of each event. The default is ``cursorSelection``.
    ///   - field: The name of the subscription field. The default is `changes`.
    /// - Returns: The document.
    static func subscription(
        after cursor: String?,
        _ arguments: String = "",
        selecting selection: String = cursorSelection,
        field: String = "changes"
    ) -> String {
        let after = cursor.map { cursor in #"after: "\#(cursor)""# }
        let list = [after, arguments.isEmpty ? nil : arguments].compactMap(\.self)
        let argumentText = list.isEmpty ? "" : "(\(list.joined(separator: ", ")))"
        return "subscription { \(field)\(argumentText) \(selection) }"
    }

    /// Subscribes to the changes of an engine.
    ///
    /// - Parameters:
    ///   - cursor: The cursor to resume after, or `nil` for the live changes only.
    ///   - arguments: The other arguments of the field, or `""` for none.
    ///   - selection: The selection of each event. The default is ``cursorSelection``.
    ///   - graph: The engine.
    /// - Returns: The stream of the responses, one for each event.
    static func subscribe(
        after cursor: String?,
        _ arguments: String = "",
        selecting selection: String = cursorSelection,
        on graph: KanbanGraph
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await SubscriptionTests.subscribe(subscription(after: cursor, arguments, selecting: selection), on: graph)
    }

    /// Gives the `changes` object of the `data` of one event.
    ///
    /// - Parameters:
    ///   - event: The response JSON text of the event.
    ///   - field: The name of the subscription field in `data`. The default is `changes`.
    /// - Returns: The object.
    /// - Throws: An error that shows the event when `data` has no such object.
    static func change(of event: String, field: String = "changes") throws -> [String: Any] {
        try KanbanGraphTests.object(named: field, in: event)
    }

    /// Gives one text field of the change of an event.
    ///
    /// - Parameters:
    ///   - name: The name of the field, for example `txn`.
    ///   - event: The response JSON text of the event.
    /// - Returns: The text.
    /// - Throws: An error that shows the event when the change has no such text field.
    static func text(_ name: String, of event: String) throws -> String {
        try #require(change(of: event)[name] as? String, "\(event)")
    }

    /// Gives one id list of the change of an event.
    ///
    /// - Parameters:
    ///   - name: The name of the list: `added`, `changed`, or `removed`.
    ///   - event: The response JSON text of the event.
    /// - Returns: The ids, in the order of the list.
    /// - Throws: An error that shows the event when the change has no such list.
    static func ids(_ name: String, of event: String) throws -> [String] {
        try #require(change(of: event)[name] as? [String], "\(event)")
    }

    /// Gives the ids of the updates of an event whose kind is one of some kinds, in the order of the updates.
    ///
    /// - Parameters:
    ///   - kinds: The kinds.
    ///   - event: The response JSON text of the event.
    /// - Returns: The ids.
    /// - Throws: An error that shows the event when the change has no updates.
    static func updateIDs(ofKinds kinds: Set<UpdateKind>, in event: String) throws -> [String] {
        let updates = try #require(change(of: event)["updates"] as? [[String: Any]], "\(event)")
        return updates.compactMap { update in
            let kind = (update["kind"] as? String).flatMap(UpdateKind.init(rawValue:))
            guard let kind, kinds.contains(kind) else {
                return nil
            }
            return update["id"] as? String
        }
    }

    /// Runs one mutation field and gives the transaction of the call.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - graph: The engine.
    /// - Returns: The transaction ULID text.
    static func commit(_ field: String, on graph: KanbanGraph) async throws -> String {
        let response = try await CommentTests.run(field, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        return try await SubscriptionTests.latestTxn(on: graph)
    }

    /// Changes the title of a task, and gives the transaction of the call.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - title: The new title.
    ///   - graph: The engine.
    /// - Returns: The transaction ULID text.
    static func retitle(_ task: ULID, to title: String, on graph: KanbanGraph) async throws -> String {
        try await commit(UndoTests.titleField(title, of: task), on: graph)
    }

    /// Gives the cursor of the event after the newest change of a log: the same epoch, and the next sequence number
    /// (the wire form `<epoch>:<sequence>` of the toolkit `ChangeLog`).
    ///
    /// - Parameter cursor: The cursor of the newest change.
    /// - Returns: The cursor after it.
    /// - Throws: An error when the cursor is not of the wire form.
    static func cursor(after cursor: String) throws -> String {
        let parts = cursor.split(separator: ":")
        let sequence = try #require(parts.last.flatMap { last in UInt64(last) }, "\(cursor)")
        return "\(parts.dropLast().joined(separator: ":")):\(sequence + 1)"
    }

    /// The title that a pulled transaction gives the fixture task.
    static let pulledTitle = "Pulled title"

    /// The title of the task that a pulled transaction adds.
    static let pulledTaskTitle = "Pulled task"

    /// Writes two transactions of two nodes to the log files of a board, as a `git pull` that brings two commits
    /// does: a new title of a task, and a new task. The file watcher applies them in one batch or in two batches.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task to give a new title.
    ///   - ids: The ULID source of the task id, the event ids, and the transaction ids.
    ///   - root: The root directory of the repo of the board.
    /// - Returns: The transaction ULID texts, in the order of the writes.
    static func pullTwoTransactions(
        retitling task: ULID,
        mintingFrom ids: inout FixedULIDSource,
        intoRepoAt root: URL
    ) throws -> [String] {
        let log = EventLog(repositoryAt: root)
        let retitled = SubscriptionTests.nextTxn(of: ids)
        let title = try ReplayTests.titlePatch(setting: pulledTitle, of: .task(task))
        try KanbanGraphTests.append(title, mintingFrom: &ids, to: log)
        let newTask = ids.makeULID()
        let added = SubscriptionTests.nextTxn(of: ids)
        try KanbanGraphTests.writeTask(newTask, titled: pulledTaskTitle, mintingFrom: &ids, to: log)
        return [retitled, added]
    }

    // MARK: - Read, then subscribe

    @Test("{ cursor } and then changes(after:) give each change after the read, one time each, in order")
    func changesAfterCursorGiveEachLaterChangeOnce() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        _ = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let cursor = try await Self.cursor(on: graph)
        let between = try await Self.retitle(task, to: KanbanGraphTests.taskTitle, on: graph)
        let stream = try await Self.subscribe(after: cursor, on: graph)
        let later = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let events = try await SubscriptionTests.events(2, of: stream, afterChangeAt: directory.url)
        #expect(try events.map { event in try Self.text("txn", of: event) } == [between, later])
        await graph.close()
    }

    @Test("The cursor of each event resumes after that event, and the root cursor is the cursor of the newest change")
    func eventCursorResumesAfterEvent() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let live = try await Self.subscribe(after: nil, on: graph)
        _ = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let second = try await Self.retitle(task, to: KanbanGraphTests.taskTitle, on: graph)
        let events = try await SubscriptionTests.events(2, of: live, afterChangeAt: directory.url)
        let first = try Self.text("cursor", of: events[0])
        let resumed = try await Self.subscribe(after: first, on: graph)
        let replayed = try await SubscriptionTests.events(1, of: resumed, afterChangeAt: directory.url)
        #expect(try Self.text("txn", of: replayed[0]) == second)
        #expect(try Self.text("cursor", of: replayed[0]) == Self.text("cursor", of: events[1]))
        #expect(try await Self.cursor(on: graph) == Self.text("cursor", of: events[1]))
        await graph.close()
    }

    @Test("Board.cursor and the cursor of Board.history are the root cursor of the read")
    func boardAndHistoryCursorsAreRootCursor() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        _ = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let response = try await KanbanGraphTests.execute(
            "{ cursor board { cursor history(first: 1) { cursor } } }",
            on: graph
        )
        let root = try #require(KanbanGraphTests.data(of: response)["cursor"] as? String, "\(response)")
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let history = try #require(board["history"] as? [[String: Any]], "\(response)")
        #expect(board["cursor"] as? String == root)
        #expect(history.first?["cursor"] as? String == root)
        await graph.close()
    }

    // MARK: - Changes from outside the engine

    @Test("A change that the file watcher applies is after the cursor of a read before it")
    func watcherChangeIsAfterEarlierCursor() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let cursor = try await Self.cursor(on: graph)
        let lineTxn = SubscriptionTests.nextTxn(of: ids)
        let log = EventLog(repositoryAt: directory.url)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let stream = try await Self.subscribe(after: cursor, on: graph)
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: log.fileURL(for: .task(task)))
        #expect(try Self.text("txn", of: events[0]) == lineTxn)
        #expect(try Self.text("cursor", of: events[0]) != cursor)
        await graph.close()
    }

    @Test("Two transactions of a pull, with ULIDs older than a commit of this process, each get a cursor")
    func pulledTransactionsEachGetCursor() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        _ = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let cursor = try await Self.cursor(on: graph)
        let pulled = try Self.pullTwoTransactions(retitling: task, mintingFrom: &ids, intoRepoAt: directory.url)
        let stream = try await Self.subscribe(after: cursor, on: graph)
        let folder = EventLog(repositoryAt: directory.url).fileURL(for: .task(task)).deletingLastPathComponent()
        let events = try await SubscriptionTests.events(2, of: stream, afterChangeAt: folder)
        // FSEvents can give the two writes in one batch or in two batches, and two batches can come in either order.
        let txns = try events.map { event in try Self.text("txn", of: event) }
        #expect(txns.sorted() == pulled.sorted())
        let cursors = try events.map { event in try Self.text("cursor", of: event) }
        #expect(Set(cursors + [cursor]).count == 3)
        let resumed = try await Self.subscribe(after: cursors[0], on: graph)
        let rest = try await SubscriptionTests.events(1, of: resumed, afterChangeAt: folder)
        #expect(try Self.text("txn", of: rest[0]) == txns[1])
        await graph.close()
    }

    // MARK: - RESYNC_REQUIRED

    @Test("A cursor whose changes left the buffer of the change log gives RESYNC_REQUIRED, and the stream ends")
    func cursorOutsideBufferNeedsResync() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let host = HostFixture.makeHost(keepingChanges: Self.smallCapacity)
        let graph = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let cursor = try await Self.cursor(on: graph)
        _ = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        _ = try await Self.retitle(task, to: KanbanGraphTests.taskTitle, on: graph)
        let stream = try await Self.subscribe(after: cursor, on: graph)
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == SubscriptionTests.oneEvent)
        #expect(code == Self.resyncCode)
        await host.close()
    }

    @Test("A cursor from before a restart of the engine gives RESYNC_REQUIRED, and the stream ends")
    func cursorOfEarlierRunNeedsResync() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let first = try KanbanGraphTests.makeGraph(at: directory.url)
        let cursor = try await Self.cursor(on: first)
        await first.close()
        let restarted = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(after: cursor, on: restarted)
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == SubscriptionTests.oneEvent)
        #expect(code == Self.resyncCode)
        await restarted.close()
    }

    @Test(
        "A cursor after the newest change, and a text that is no cursor, give RESYNC_REQUIRED",
        arguments: [true, false]
    )
    func cursorPastNewestNeedsResync(isPastNewest: Bool) async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let cursor = isPastNewest ? try Self.cursor(after: try await Self.cursor(on: graph)) : "not-a-cursor"
        let stream = try await Self.subscribe(after: cursor, on: graph)
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == SubscriptionTests.oneEvent)
        #expect(code == Self.resyncCode)
        await graph.close()
    }

    // MARK: - Filter and id lists

    @Test("A filtered subscriber gets the replayed and the live changes that its filter keeps, in order")
    func filteredSubscriberKeepsOrder() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let cursor = try await Self.cursor(on: graph)
        let added = try await Self.commit(AddUpdateTaskTests.addTask(with: ""), on: graph)
        _ = try await Self.commit(TagMutationTests.addTag(named: TagMutationTests.bug), on: graph)
        let retitled = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let stream = try await Self.subscribe(after: cursor, #"filter: "~task""#, on: graph)
        let later = try await Self.retitle(task, to: KanbanGraphTests.taskTitle, on: graph)
        let events = try await SubscriptionTests.events(3, of: stream, afterChangeAt: directory.url)
        #expect(try events.map { event in try Self.text("txn", of: event) } == [added, retitled, later])
        await graph.close()
    }

    @Test("added, changed, and removed hold the ids of the created or restored, updated, and deleted nodes")
    func idListsFollowUpdateKinds() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(after: nil, selecting: Self.idListSelection, on: graph)
        let task = try await CrossRepoFixture.addTask(with: "", on: graph)
        let tag = try await Design.PortabilityTests.id(
            runningField: TagMutationTests.addTag(named: TagMutationTests.bug),
            named: MutationName.addTag,
            on: graph
        )
        let column = try await Design.PortabilityTests.id(
            runningField: AddUpdateTaskTests.doneColumn,
            named: MutationName.addColumn,
            on: graph
        )
        let ulid = try AddUpdateTaskTests.firstTask(in: task)
        _ = try await Self.retitle(ulid, to: KanbanGraphTests.laterTitle, on: graph)
        _ = try await CommentTests.run(TaskOperationTests.taskField(MutationName.deleteTask, of: ulid), on: graph)
        _ = try await CommentTests.run(TaskOperationTests.taskField(MutationName.undeleteTask, of: ulid), on: graph)
        let events = try await SubscriptionTests.events(6, of: stream, afterChangeAt: directory.url)
        for event in events {
            #expect(try Self.ids("added", of: event) == Self.updateIDs(ofKinds: [.created, .restored], in: event))
            #expect(try Self.ids("changed", of: event) == Self.updateIDs(ofKinds: [.updated], in: event))
            #expect(try Self.ids("removed", of: event) == Self.updateIDs(ofKinds: [.deleted], in: event))
        }
        let actor = ColumnActorTests.id(of: KanbanGraphTests.sessionActor.ref)
        #expect(try Set(Self.ids("added", of: events[0])).isSuperset(of: [task, actor]))
        #expect(try Self.ids("added", of: events[1]).contains(tag))
        #expect(try Self.ids("added", of: events[2]).contains(column))
        #expect(try Self.ids("changed", of: events[3]).contains(task))
        #expect(try Self.ids("removed", of: events[4]) == [task])
        #expect(try Self.ids("added", of: events[5]).contains(task))
        await graph.close()
    }

    // MARK: - Alias

    @Test("kanbanChanges is an alias of changes, and the event shows the rewrite in extensions.rewrites")
    func kanbanChangesIsAliasOfChanges() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let cursor = try await Self.cursor(on: graph)
        let txn = try await Self.retitle(task, to: KanbanGraphTests.laterTitle, on: graph)
        let document = Self.subscription(after: cursor, field: "kanbanChanges")
        let stream = try await SubscriptionTests.subscribe(document, on: graph)
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: directory.url)
        #expect(try Self.change(of: events[0], field: "kanbanChanges")["txn"] as? String == txn)
        let extensions = try #require(KanbanGraphTests.object(of: events[0])["extensions"] as? [String: Any])
        let rewrites = try #require(extensions["rewrites"] as? [[String: Any]], "\(events[0])")
        #expect(rewrites.contains { rewrite in rewrite["from"] as? String == "kanbanChanges" })
        #expect(rewrites.contains { rewrite in rewrite["to"] as? String == "changes" })
        await graph.close()
    }

    // MARK: - One log for each board engine

    @Test("Two session views of one board read one change log: a cursor of one view resumes on the other")
    func sessionViewsShareChangeLog() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let first = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let second = try await host.session(workingDirectory: directory.url, actor: Self.secondActor)
        let cursor = try await Self.cursor(on: first)
        #expect(try await Self.cursor(on: second) == cursor)
        let task = try await CrossRepoFixture.addTask(with: "", on: second)
        let stream = try await Self.subscribe(after: cursor, selecting: Self.idListSelection, on: first)
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: directory.url)
        #expect(try Self.ids("added", of: events[0]).contains(task))
        await host.close()
    }

    @Test("cursor(board:) gives the cursor of a related board, and changes(after:, board:) resumes after it")
    func relatedBoardCursorResumesItsChanges() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libKey = try CrossRepoWriteTests.libKey()
        let response = try await KanbanGraphTests.execute(#"{ cursor(board: "\#(libKey)") }"#, on: app)
        let cursor = try #require(KanbanGraphTests.data(of: response)["cursor"] as? String, "\(response)")
        let libTask = try await CrossRepoWriteTests.addLibTask(on: app)
        let stream = try await Self.subscribe(
            after: cursor,
            #"board: "\#(libKey)""#,
            selecting: Self.idListSelection,
            on: app
        )
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: repos.lib)
        #expect(try Self.ids("added", of: events[0]).contains(libTask))
        await app.close()
    }
}
