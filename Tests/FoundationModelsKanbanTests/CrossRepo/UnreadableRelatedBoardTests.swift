import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests a related board that cannot be read (divergence.md Q7, X9, X12): the call continues, each dependency on a
/// task of that board is not done, the response has a warning that names the board, and the change feed keeps
/// sending the changes of the boards that load. A related board of the old Rust kanban still stops the call with
/// `INCOMPATIBLE_BOARD` (divergence.md Q6).
///
/// Each test makes real git repos in a ``GitSandbox``. No test reads or changes the `.kanban/` directory of this repo.
@Suite("Cross-repo: a related board that cannot be read", .watcherBudget)
struct UnreadableRelatedBoardTests {
    /// The code of the warning of a related board that cannot be read.
    static let warningCode = "BOARD_UNREADABLE"

    /// The selection of the `ready` field of a task.
    static let readySelection = "{ ready }"

    /// The name of a Rust-only file that makes a `.kanban/` directory incompatible (divergence.md Q6).
    static let rustLogName = "mcp.17281.log"

    /// The POSIX permissions of a log file that its owner can read and write, and that each other user can read.
    static let readablePermissions = 0o644

    // MARK: - Fixture

    /// A way to make a related board that cannot be read.
    enum Breakage: CaseIterable, Sendable, CustomTestStringConvertible {
        /// The log file of the target task has no read permission.
        case noReadPermission

        /// A log path in the task directory is a directory, so the loader cannot read it as a file.
        case brokenLog

        /// The name of the case in the test output.
        var testDescription: String {
            switch self {
            case .noReadPermission: "a log file with no read permission"
            case .brokenLog: "a log path that is a directory"
            }
        }

        /// Makes the board of a repo unreadable.
        ///
        /// - Parameters:
        ///   - target: The full URI of a task of the board.
        ///   - root: The root directory of the repo.
        /// - Returns: The log path that the breakage changed.
        /// - Throws: An error when the URI holds no ULID, or when a file cannot be changed.
        @discardableResult
        func apply(toTask target: String, inRepoAt root: URL) throws -> URL {
            let log = EventLog(repositoryAt: root)
            switch self {
            case .noReadPermission:
                let file = log.fileURL(for: .task(try AddUpdateTaskTests.firstTask(in: target)))
                try FileManager.default.setAttributes(
                    [.posixPermissions: KanbanHostTests.unreadablePermissions],
                    ofItemAtPath: file.path
                )
                return file
            case .brokenLog:
                let directory = log.fileURL(for: .task(ULID()))
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return directory
            }
        }

        /// Makes a board that ``apply(toTask:inRepoAt:)`` made unreadable readable again. For a log file with no
        /// read permission, the function gives the read permission back to the file. For a log path that is a
        /// directory, the function removes the directory.
        ///
        /// - Parameter changed: The log path that ``apply(toTask:inRepoAt:)`` gave.
        /// - Throws: An error when the file or the directory cannot be changed.
        func repair(_ changed: URL) throws {
            switch self {
            case .noReadPermission:
                try FileManager.default.setAttributes(
                    [.posixPermissions: UnreadableRelatedBoardTests.readablePermissions],
                    ofItemAtPath: changed.path
                )
            case .brokenLog:
                try FileManager.default.removeItem(at: changed)
            }
        }
    }

    /// Two repos side by side: a task of the related repo, and a task of the current repo that depends on it.
    struct Dependency {
        /// The repos.
        let repos: CrossRepoFixture.SideBySide

        /// The full URI of the task of the current repo.
        let task: String

        /// The full URI of the task of the related repo.
        let target: String
    }

    /// Makes the repos of a ``Dependency``. The engines of the setup are closed when the function returns.
    ///
    /// - Returns: The repos and the two tasks.
    /// - Throws: An error when a git command fails, or when a call fails.
    static func makeDependency() async throws -> Dependency {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        await app.close()
        return Dependency(repos: repos, task: task, target: target)
    }

    /// Makes the repos of a ``Dependency``, and then makes the related board unreadable.
    ///
    /// - Parameter breakage: The way to make the related board unreadable.
    /// - Returns: The repos and the two tasks.
    /// - Throws: An error when a git command fails, when a call fails, or when a file cannot be changed.
    static func makeBrokenDependency(_ breakage: Breakage) async throws -> Dependency {
        let dependency = try await makeDependency()
        try breakage.apply(toTask: dependency.target, inRepoAt: dependency.repos.lib)
        return dependency
    }

    /// Checks that a response has one warning, for the related board of the repos, with its key and its path.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - repos: The repos.
    /// - Throws: An error when the response has no warnings, or when the key of the related repo cannot be made.
    static func expectUnreadableWarning(in response: String, for repos: CrossRepoFixture.SideBySide) throws {
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [warningCode])
        let message = try #require(warnings.first?.message)
        let directory = EventLog(repositoryAt: repos.lib.resolvingSymlinksInPath()).directory.path
        #expect(message.contains(try CrossRepoWriteTests.libKey()), "\(message)")
        #expect(message.contains(directory), "\(message)")
    }

    // MARK: - Calls

    @Test(
        "{ board { name } } with a related board that cannot be read does not fail, and warns with its key and path",
        arguments: Breakage.allCases
    )
    func nameQueryWarnsAboutRelatedBoard(breakage: Breakage) async throws {
        let dependency = try await Self.makeBrokenDependency(breakage)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let response = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app)
        await app.close()
        let board = try KanbanGraphTests.object(named: "board", in: response)
        #expect(board["name"] as? String == dependency.repos.app.lastPathComponent)
        try Self.expectUnreadableWarning(in: response, for: dependency.repos)
    }

    @Test("A document that does not parse, with a related board that cannot be read, fails and warns about the board")
    func parseFailureWarnsAboutRelatedBoard() async throws {
        let dependency = try await Self.makeBrokenDependency(.brokenLog)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let response = try await KanbanGraphTests.execute(ErrorCoverageTests.syntaxErrorDocument, on: app)
        await app.close()
        let errors = try NameRewriteTests.errors(of: response)
        #expect(errors.map(ErrorCoverageTests.code(of:)) == ["GRAPHQL_PARSE_FAILED"], "\(response)")
        try Self.expectUnreadableWarning(in: response, for: dependency.repos)
    }

    @Test(
        "A task that depends on a task of a related board that cannot be read is not ready",
        arguments: Breakage.allCases
    )
    func dependentTaskIsNotReady(breakage: Breakage) async throws {
        let dependency = try await Self.makeBrokenDependency(breakage)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let query = try CrossRepoReadTests.query(of: dependency.task, selecting: Self.readySelection)
        let response = try await KanbanGraphTests.execute(query, on: app)
        await app.close()
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let task = try #require(board["task"] as? [String: Any], "\(response)")
        #expect(task["ready"] as? Bool == false)
        try Self.expectUnreadableWarning(in: response, for: dependency.repos)
    }

    @Test("A related Rust board still stops a call with INCOMPATIBLE_BOARD")
    func relatedRustBoardStillStopsCall() async throws {
        let dependency = try await Self.makeDependency()
        try IncompatibleBoardTests.RustOnlyPath.file(Self.rustLogName).make(inRepoAt: dependency.repos.lib)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let response = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app)
        await app.close()
        #expect(response == (try IncompatibleBoardTests.libIncompatibleResponse(in: dependency.repos)))
    }

    // MARK: - Change feed

    @Test(
        "A subscriber gets the changes of the current board when a related board cannot be read",
        arguments: Breakage.allCases
    )
    func subscriberGetsChangesOfCurrentBoard(breakage: Breakage) async throws {
        let dependency = try await Self.makeBrokenDependency(breakage)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments)
        let stream = try await SubscriptionTests.subscribe(document, on: app)
        _ = try await CrossRepoFixture.addTask(with: "", on: app)
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent, of: stream, afterChangeAt: dependency.repos.app
        )
        await app.close()
        let event = try #require(events.first, "The subscriber got no event")
        #expect(try KanbanGraphTests.data(of: event)["changes"] != nil, "\(event)")
    }

    @Test(
        "A subscription to a related board that cannot be read gives NOT_FOUND for the board, and ends",
        arguments: Breakage.allCases
    )
    func subscriptionToUnreadableBoardEnds(breakage: Breakage) async throws {
        let dependency = try await Self.makeBrokenDependency(breakage)
        let app = try GitGraphFixture.makeGraph(at: dependency.repos.app)
        let document = SubscriptionTests.subscription(#"(board: "\#(try CrossRepoWriteTests.libKey())")"#)
        let stream = try await SubscriptionTests.subscribe(document, on: app)
        let events = try await SubscriptionTests.allEvents(of: stream)
        await app.close()
        let event = try #require(events.first, "The subscription ended with no response")
        let error = try #require(try NameRewriteTests.errors(of: event).first, "\(event)")
        #expect(events.count == SubscriptionTests.oneEvent)
        #expect((error["extensions"] as? [String: Any])?["code"] as? String == "NOT_FOUND", "\(event)")
    }

    @Test("A subscriber gets the change of a different process that adds a dependency on a related Rust board")
    func subscriberGetsChangeWithRustDependency() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        try IncompatibleBoardTests.RustOnlyPath.file(Self.rustLogName).make(inRepoAt: repos.lib)
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments)
        let stream = try await SubscriptionTests.subscribe(document, on: app)
        let patch = try PatchInput(
            node: .task(AddUpdateTaskTests.firstTask(in: task)),
            add: [PropertyName.dependsOn: [.remote(try NodeURI(parsing: target))]]
        )
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep))
        let log = EventLog(repositoryAt: repos.app)
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: log)
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent, of: stream, afterChangeAt: log.directory
        )
        await app.close()
        #expect(events.count == SubscriptionTests.oneEvent)
    }

    // MARK: - Load again after a change

    /// Makes a host that reads the worktree tops and the board keys from git, and that reports its loads to a
    /// recorder.
    ///
    /// - Parameter recorder: The recorder of the loads.
    /// - Returns: The host.
    static func makeHost(recordedBy recorder: UnreadableBoardRecorder) -> KanbanHost {
        HostFixture.makeHost(
            readingKeyWith: BoardKey.read(fromRepoAt:),
            findingTopWith: BoardKey.worktreeTop(of:),
            observingLoadsWith: recorder
        )
    }

    /// Tells if a response has no `extensions.warnings` key, and thus no warning. The `extensions` object of a call
    /// that writes also has `txn` (divergence.md §19).
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: `true` when the response has no warning.
    /// - Throws: An error when the response is not a JSON object.
    static func hasNoWarning(_ response: String) throws -> Bool {
        let extensions = try KanbanGraphTests.object(of: response)["extensions"] as? [String: Any]
        return extensions?["warnings"] == nil
    }

    @Test(
        "A second call does not load again a related board that could not load, while its files do not change",
        arguments: Breakage.allCases
    )
    func secondCallDoesNotLoadAgain(breakage: Breakage) async throws {
        let dependency = try await Self.makeBrokenDependency(breakage)
        let recorder = UnreadableBoardRecorder()
        let host = Self.makeHost(recordedBy: recorder)
        let app = try await host.session(workingDirectory: dependency.repos.app, actor: KanbanHostTests.firstActor)
        let first = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app)
        let second = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app)
        await host.close()
        try Self.expectUnreadableWarning(in: first, for: dependency.repos)
        try Self.expectUnreadableWarning(in: second, for: dependency.repos)
        #expect(recorder.loadCount(ofBoardAt: dependency.repos.lib) == 1)
    }

    @Test(
        "After a repair of the files of a related board that could not load, the next call reads the board",
        arguments: Breakage.allCases
    )
    func changeOfFilesLoadsAgain(breakage: Breakage) async throws {
        let dependency = try await Self.makeDependency()
        let broken = try breakage.apply(toTask: dependency.target, inRepoAt: dependency.repos.lib)
        let recorder = UnreadableBoardRecorder()
        let host = Self.makeHost(recordedBy: recorder)
        let app = try await host.session(workingDirectory: dependency.repos.app, actor: KanbanHostTests.firstActor)
        let first = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app)
        try Self.expectUnreadableWarning(in: first, for: dependency.repos)
        try breakage.repair(broken)
        let isRead = try await recorder.waitForChange(waitingFor: "a change of the repaired board", at: broken) {
            try Self.hasNoWarning(try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: app))
        }
        await host.close()
        #expect(isRead)
    }
}

// MARK: - Recorder

/// Records each load of a board, and gives each change of a board that could not load, so that a test waits for the
/// change and then for its effect.
final class UnreadableBoardRecorder: BoardLoadObserver {
    /// The root folder of each load that started, behind a lock, because the loads run on different threads.
    private let starts = Mutex<[URL]>([])

    /// The root folder of each board that could not load and whose files changed, in order.
    private let changes: AsyncStream<URL>

    /// Gives the elements of ``changes``.
    private let changeSink: AsyncStream<URL>.Continuation

    /// Makes a recorder.
    init() {
        (changes, changeSink) = AsyncStream.makeStream()
    }

    /// Gives the number of loads of one board that started.
    ///
    /// - Parameter root: The root folder of the board.
    /// - Returns: The number of loads.
    func loadCount(ofBoardAt root: URL) -> Int {
        starts.withLock { starts in starts.count { start in start.canonicalPath == root.canonicalPath } }
    }

    /// Records the start of a load.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidStart(at root: URL) async {
        starts.withLock { starts in starts.append(root) }
    }

    /// Does nothing: the recorder counts only the starts.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidFinish(at root: URL) {}

    /// Records a change of a board that could not load.
    ///
    /// - Parameter root: The root folder of the board.
    func unreadableBoardDidChange(at root: URL) {
        changeSink.yield(root)
    }

    /// Waits until the host saw a change of a board that could not load, and the effect of the change shows
    /// (``FolderEventWait/change(in:waitingFor:at:until:)``). Call it one time for each recorder.
    ///
    /// - Parameters:
    ///   - change: The change that the test waits for. The failure message at the time limit names it.
    ///   - path: The file or folder that the test changed. The failure message at the time limit names it.
    ///   - isShown: Tells if the effect of the change shows. The wait asks it after each change.
    /// - Returns: `true` when the effect shows, and `false` when the changes end first.
    /// - Throws: ``FolderEventTimeout`` when the effect does not show before the time limit, or an error that
    ///   `isShown` throws.
    func waitForChange(
        waitingFor change: String,
        at path: URL,
        until isShown: @escaping @Sendable () async throws -> Bool
    ) async throws -> Bool {
        try await FolderEventWait.change(in: changes, waitingFor: change, at: path, until: isShown)
    }
}
