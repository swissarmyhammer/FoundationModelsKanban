import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsKanban

/// The viewers of the tests of the `kanban` endpoint (EXTRAS-5, EXTRAS-9 rule 4).
enum KanbanViewerFixture {
    /// The id of the one session that the viewers own.
    static let sessionID = "session-1"

    /// A device of the user, for example the Mac app.
    static let userDevice = GraphQLViewer(clientId: "mac", trust: .userDevice, ownedSessions: [sessionID])

    /// A client that is not a device of the user.
    static let external = GraphQLViewer(clientId: "remote", trust: .external, ownedSessions: [sessionID])
}

/// Tests the reach of a viewer of the `kanban` endpoint (KANBAN-5; EXTRAS-9 rev 2, rule 4): an `external` viewer
/// reads and writes only the board of the folder of the endpoint, and each ref to a different board is refused with
/// `UNREACHABLE_BOARD`, the same for a board that exists and a board that does not. A `nil` viewer and a `userDevice`
/// viewer reach each board, as before.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/`
/// directory of this repo.
@Suite("Cross-repo: an external viewer reaches only the board of its folder", .watcherBudget)
struct ViewerReachTests {
    /// The `extensions.code` of a ref to a board that the viewer cannot reach.
    static let unreachableCode = "UNREACHABLE_BOARD"

    /// The name of a sibling folder that does not exist.
    static let missingFolderName = "no-such-repo"

    /// The forms of a board ref that name the related repo: its key, its path, and its board URI.
    enum RefForm: String, CaseIterable, Sendable {
        /// The board key, for example `github.com/owner/lib`.
        case key

        /// The path of the repo folder.
        case path

        /// The board URI, for example `kanban://github.com/owner/lib/board`.
        case uri

        /// Gives the ref of the related repo in this form.
        ///
        /// - Parameter repos: The repos of the test.
        /// - Returns: The ref.
        /// - Throws: An error when the remote URL of the related repo is not valid.
        func libReference(in repos: CrossRepoFixture.SideBySide) throws -> String {
            try reference(key: CrossRepoWriteTests.libKey(), folder: repos.lib)
        }

        /// Gives the ref of a board that does not exist, in this form.
        ///
        /// - Parameter repos: The repos of the test.
        /// - Returns: The ref.
        func missingReference(in repos: CrossRepoFixture.SideBySide) -> String {
            reference(
                key: CrossRepoReadTests.missingKey,
                folder: repos.sandbox.root.appending(path: ViewerReachTests.missingFolderName)
            )
        }

        /// Gives a ref in this form.
        ///
        /// - Parameters:
        ///   - key: The board key.
        ///   - folder: The repo folder.
        /// - Returns: The ref.
        private func reference(key: String, folder: URL) -> String {
            switch self {
            case .key: key
            case .path: folder.path
            case .uri: "\(NodeURI.scheme)\(key)\(LocalRef.separator)\(LocalRef.board)"
            }
        }
    }

    /// One document that names a different board, for the refusal tests.
    struct RefusedCase: CustomTestStringConvertible, Sendable {
        /// What the document does, for the test name.
        let testDescription: String

        /// Makes the document from the ref of the board and the full URI of a task of the current board.
        let document: @Sendable (_ board: String, _ task: String) -> String
    }

    /// The documents that name a different board by a board ref.
    static let refusedCases = [
        RefusedCase(testDescription: "board(id:)") { board, _ in #"{ board(id: "\#(board)") { name } }"# },
        RefusedCase(testDescription: "addTask with a board field") { board, _ in
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: CrossRepoWriteTests.boardField(board)))
        },
        RefusedCase(testDescription: "moveTask(board:)") { board, task in
            Self.transfer(MutationName.moveTask, task, to: board)
        },
        RefusedCase(testDescription: "copyTask") { board, task in
            Self.transfer(MutationName.copyTask, task, to: board)
        },
        RefusedCase(testDescription: "undoChange with a board field") { board, _ in
            AddUpdateTaskTests.mutation(
                of: UndoTests.reverseField(MutationName.undoChange, with: CrossRepoWriteTests.boardField(board))
            )
        },
        RefusedCase(testDescription: "collectBoards") { board, _ in
            AddUpdateTaskTests.mutation(of: CollectBoardsTests.collectField(of: [board]))
        },
    ]

    // MARK: - The board of the folder

    @Test("An external viewer reads and writes the board of its folder, also by its key and its path")
    func externalViewerUsesOwnBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let added = try await Self.execute(
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: "")),
            as: KanbanViewerFixture.external,
            on: app
        )
        #expect(try CrossRepoWriteTests.hasNoErrors(added), "\(added)")
        for reference in [try CrossRepoWriteTests.appKey(), repos.app.path] {
            let response = try await Self.execute(
                #"{ board(id: "\#(reference)") { name } }"#,
                as: KanbanViewerFixture.external,
                on: app
            )
            #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
            #expect(try KanbanGraphTests.object(named: "board", in: response)["name"] as? String == BoardLocatorTests.appName)
        }
        await app.close()
    }

    // MARK: - Refusals

    @Test(
        "An external viewer is refused on a sibling board by each ref form, and nothing is written there",
        arguments: refusedCases,
        RefForm.allCases
    )
    func externalViewerIsRefused(refusedCase: RefusedCase, form: RefForm) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        let document = refusedCase.document(try form.libReference(in: repos), task)
        let response = try await Self.execute(document, as: KanbanViewerFixture.external, on: app)
        #expect(try Self.errorCodes(of: response) == [Self.unreachableCode], "\(response)")
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: repos.lib))
        await app.close()
    }

    @Test(
        "The refusal of a sibling board is the same as the refusal of a board that does not exist",
        arguments: refusedCases,
        RefForm.allCases
    )
    func refusalDoesNotRevealBoard(refusedCase: RefusedCase, form: RefForm) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        let (lib, missing) = (try form.libReference(in: repos), form.missingReference(in: repos))
        let viewer = KanbanViewerFixture.external
        let libResponse = try await Self.execute(refusedCase.document(lib, task), as: viewer, on: app)
        let missingResponse = try await Self.execute(refusedCase.document(missing, task), as: viewer, on: app)
        #expect(libResponse.replacingOccurrences(of: lib, with: missing) == missingResponse)
        await app.close()
    }

    @Test("An external viewer is refused on a task URI of a sibling board, the same as on a board that does not exist")
    func externalViewerIsRefusedOnNodeURI() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libTask = try await CrossRepoWriteTests.addLibTask(on: app)
        let libKey = try CrossRepoWriteTests.libKey()
        let missingTask = libTask.replacingOccurrences(of: libKey, with: CrossRepoReadTests.missingKey)
        let viewer = KanbanViewerFixture.external
        let libResponse = try await Self.execute(Self.nodeQuery(libTask), as: viewer, on: app)
        let missingResponse = try await Self.execute(Self.nodeQuery(missingTask), as: viewer, on: app)
        #expect(try Self.errorCodes(of: libResponse) == [Self.unreachableCode], "\(libResponse)")
        #expect(libResponse.replacingOccurrences(of: libKey, with: CrossRepoReadTests.missingKey) == missingResponse)
        await app.close()
    }

    @Test(
        "An external viewer is refused on a field that reaches the boards of the scan or names a sibling board",
        arguments: [
            "{ boards { key } }",
            "mutation { repairLinks(input: { reach: true }) { node } }",
            #"{ checkLinks(boards: ["\#(BoardLocatorTests.libName)"]) { node } }"#,
        ]
    )
    func externalViewerIsRefusedOnOtherBoardsField(document: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let response = try await Self.execute(document, as: KanbanViewerFixture.external, on: app)
        #expect(try Self.errorCodes(of: response) == [Self.unreachableCode], "\(response)")
        await app.close()
    }

    @Test("An external viewer is refused on a subscription to a sibling board", arguments: RefForm.allCases)
    func externalViewerIsRefusedOnSubscription(form: RefForm) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let arguments = #"(board: "\#(try form.libReference(in: repos))")"#
        let stream = try await app.subscribe(
            query: SubscriptionTests.subscription(arguments),
            variables: [:],
            operationName: nil,
            viewer: KanbanViewerFixture.external
        )
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == 1)
        #expect(code == Self.unreachableCode)
        await app.close()
    }

    @Test("An external viewer is refused on cursor(board:) of a sibling board", arguments: RefForm.allCases)
    func externalViewerIsRefusedOnCursorOfSiblingBoard(form: RefForm) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let document = #"{ cursor(board: "\#(try form.libReference(in: repos))") }"#
        let response = try await Self.execute(document, as: KanbanViewerFixture.external, on: app)
        #expect(try Self.errorCodes(of: response) == [Self.unreachableCode], "\(response)")
        await app.close()
    }

    @Test("An external viewer is refused on changes(after:) of a sibling board, with a cursor of its own board")
    func externalViewerIsRefusedOnResumeOfSiblingBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let own = try await Self.execute("{ cursor }", as: KanbanViewerFixture.external, on: app)
        let cursor = try #require(KanbanGraphTests.data(of: own)["cursor"] as? String, "\(own)")
        let arguments = #"(after: "\#(cursor)", board: "\#(try CrossRepoWriteTests.libKey())")"#
        let stream = try await app.subscribe(
            query: SubscriptionTests.subscription(arguments),
            variables: [:],
            operationName: nil,
            viewer: KanbanViewerFixture.external
        )
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == 1)
        #expect(code == Self.unreachableCode)
        await app.close()
    }

    @Test("An external viewer reads the cursor of its own board and resumes the changes of its own board after it")
    func externalViewerResumesOwnBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let own = try await Self.execute("{ cursor }", as: KanbanViewerFixture.external, on: app)
        let cursor = try #require(KanbanGraphTests.data(of: own)["cursor"] as? String, "\(own)")
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        let stream = try await app.subscribe(
            query: SubscriptionTests.subscription(#"(after: "\#(cursor)")"#, selecting: "{ added }"),
            variables: [:],
            operationName: nil,
            viewer: KanbanViewerFixture.external
        )
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: repos.app)
        let change = try KanbanGraphTests.object(named: "changes", in: try #require(events.first))
        #expect((change["added"] as? [String])?.contains(task) == true, "\(events)")
        await app.close()
    }

    @Test("An external viewer cannot undo a transaction that also changed a sibling board")
    func externalViewerIsRefusedOnCrossBoardUndo() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        let moved = try await CrossRepoTransferTests.transfer(
            MutationName.moveTask,
            task,
            with: CrossRepoWriteTests.boardField(try CrossRepoWriteTests.libKey()),
            on: app
        )
        let libEvents = try CrossRepoWriteTests.events(inRepoAt: repos.lib)
        let txn = try #require(libEvents.last).txn
        let undo = UndoTests.reverseField(MutationName.undoChange, with: UndoTests.txnInput(txn))
        let response = try await Self.execute(
            AddUpdateTaskTests.mutation(of: undo),
            as: KanbanViewerFixture.external,
            on: app
        )
        #expect(try Self.errorCodes(of: response) == [Self.unreachableCode], "\(response)")
        #expect(try CrossRepoWriteTests.events(inRepoAt: repos.lib).count == libEvents.count)
        #expect(try NodeURI(parsing: moved).boardKey == CrossRepoWriteTests.libKey())
        await app.close()
    }

    @Test("An external viewer reads no task of a sibling board through a dependency of a task of its own board")
    func externalViewerReadsNoDependencyOfSiblingBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libTask = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: libTask, on: app)
        let document = #"{ node(id: "\#(task)") { ... on Task { dependsOn { id title } unresolvedDependsOn } } }"#
        let external = try await Self.execute(document, as: KanbanViewerFixture.external, on: app)
        let node = try KanbanGraphTests.object(named: "node", in: external)
        #expect((node["dependsOn"] as? [Any])?.isEmpty == true, "\(external)")
        #expect(!external.contains(AddUpdateTaskTests.title))
        await app.close()
    }

    // MARK: - Viewers of the user

    @Test(
        "A nil viewer and a userDevice viewer read and write a sibling board, as before",
        arguments: [nil, KanbanViewerFixture.userDevice]
    )
    func userViewersReachSiblingBoard(viewer: GraphQLViewer?) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libKey = try CrossRepoWriteTests.libKey()
        let added = try await Self.execute(
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: CrossRepoWriteTests.boardField(libKey))),
            as: viewer,
            on: app
        )
        #expect(try CrossRepoWriteTests.hasNoErrors(added), "\(added)")
        let read = try await Self.execute(#"{ board(id: "\#(libKey)") { name } }"#, as: viewer, on: app)
        #expect(try KanbanGraphTests.object(named: "board", in: read)["name"] as? String == BoardLocatorTests.libName)
        let listed = try await Self.execute("{ boards { key } }", as: viewer, on: app)
        #expect(try CrossRepoWriteTests.hasNoErrors(listed), "\(listed)")
        #expect(listed.contains(libKey))
        await app.close()
    }

    // MARK: - Helpers

    /// Runs one document on an engine through the endpoint protocol, as a viewer.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - viewer: The viewer of the call, or `nil` for the agent of the session.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    static func execute(_ document: String, as viewer: GraphQLViewer?, on graph: KanbanGraph) async throws -> String {
        try await graph.execute(query: document, variables: [:], operationName: nil, viewer: viewer)
    }

    /// Gives the `extensions.code` of each error of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The codes, in the order of the errors.
    /// - Throws: An error when the response has no `errors` list.
    static func errorCodes(of response: String) throws -> [String] {
        try NameRewriteTests.errors(of: response).compactMap { error in
            (error["extensions"] as? [String: Any])?["code"] as? String
        }
    }

    /// Makes a query of the id and the title of the task of a full URI.
    ///
    /// - Parameter task: The full URI of the task.
    /// - Returns: The document.
    static func nodeQuery(_ task: String) -> String {
        #"{ node(id: "\#(task)") { id ... on Task { title } } }"#
    }

    /// Makes a mutation document that moves or copies a task to a board.
    ///
    /// - Parameters:
    ///   - operation: `moveTask` or `copyTask`.
    ///   - task: The full URI of the task.
    ///   - board: The board ref of the target board.
    /// - Returns: The document.
    static func transfer(_ operation: String, _ task: String, to board: String) -> String {
        AddUpdateTaskTests.mutation(
            of: CommentTests.nodeField(operation, naming: task, with: CrossRepoWriteTests.boardField(board))
        )
    }
}
