import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that a call loads the related boards that it reaches at the same time (divergence.md §16, L5), and that two
/// requests for the same related board at the same time wait for one load.
///
/// Each test makes real git repos in a ``GitSandbox`` and a host that reads the worktree tops and the board keys from
/// git. The load recorder of the host waits in each file load, so that two loads in sequence and two loads at the
/// same time give different event orders.
@Suite("Cross-repo: load the related boards at the same time", .watcherBudget, .timeLimit(.minutes(1)))
struct CrossRepoParallelLoadTests {
    /// The name of the second related repo.
    static let toolsName = "tools"

    /// The `origin` remote of the second related repo.
    static let toolsOrigin = "https://github.com/example/tools.git"

    /// The time that the file load of each board waits. The file load of an empty board takes much less.
    static let loadDelay = Duration.milliseconds(300)

    /// The number of related boards that a test reaches.
    static let relatedCount = 2

    /// Makes a host that reads git and that waits in each file load.
    ///
    /// - Parameter recorder: The load recorder of the host.
    /// - Returns: The host.
    static func makeSlowHost(recordedBy recorder: LoadRecorder) -> KanbanHost {
        HostFixture.makeHost(
            readingKeyWith: BoardKey.read(fromRepoAt:),
            findingTopWith: BoardKey.worktreeTop(of:),
            observingLoadsWith: recorder
        )
    }

    /// Gives the load events of some boards, in the order that they happened.
    ///
    /// - Parameters:
    ///   - repos: The repo directories of the boards.
    ///   - recorder: The load recorder of the host.
    /// - Returns: The start and the end of each file load of the boards.
    static func loadEvents(of repos: [URL], in recorder: LoadRecorder) -> [LoadEvent] {
        let paths = Set(repos.map(\.canonicalPath))
        return recorder.events.filter { event in
            paths.contains(event.root.canonicalPath) && [.loadDidStart, .loadDidFinish].contains(event.kind)
        }
    }

    /// Tells how many file loads of some boards started before the first file load of those boards ended.
    ///
    /// - Parameters:
    ///   - repos: The repo directories of the boards.
    ///   - recorder: The load recorder of the host.
    /// - Returns: The number of loads that started before the first end.
    /// - Throws: An error when no load of the boards ended.
    static func startsBeforeFirstEnd(of repos: [URL], in recorder: LoadRecorder) throws -> Int {
        let events = loadEvents(of: repos, in: recorder)
        let firstEnd = try #require(events.firstIndex { event in event.kind == .loadDidFinish })
        return events.prefix(firstEnd).count { event in event.kind == .loadDidStart }
    }

    // MARK: - Loads at the same time

    @Test("A query that names two related boards starts both loads before either load ends")
    func boardFieldsLoadAtSameTime() async throws {
        let repos = try await CrossRepoFixture.ThreeRepos.make(toolsNamed: Self.toolsName, origin: Self.toolsOrigin)
        let recorder = LoadRecorder(waitingInEachLoad: Self.loadDelay)
        let host = Self.makeSlowHost(recordedBy: recorder)
        let session = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let query = """
            { lib: board(id: "\(BoardLocatorTests.libName)") { path } \
            tools: board(id: "\(Self.toolsName)") { path } }
            """
        let response = try await KanbanGraphTests.execute(query, on: session)
        let expected = #"{"data":{"lib":{"path":"\#(repos.lib.path)"},"tools":{"path":"\#(repos.tools.path)"}}}"#
        #expect(response == expected)
        #expect(try Self.startsBeforeFirstEnd(of: [repos.lib, repos.tools], in: recorder) == Self.relatedCount)
        await host.close()
    }

    @Test("Query.boards starts the load of each related copy before any load ends, and keeps the scan order")
    func boardListLoadsAtSameTime() async throws {
        let repos = try await CrossRepoFixture.ThreeRepos.make(toolsNamed: Self.toolsName, origin: Self.toolsOrigin)
        let recorder = LoadRecorder(waitingInEachLoad: Self.loadDelay)
        let host = Self.makeSlowHost(recordedBy: recorder)
        let session = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let paths = try await CrossRepoReadTests.boardPaths(on: session)
        #expect(paths == [repos.app.path, repos.lib.path, repos.tools.path])
        #expect(try Self.startsBeforeFirstEnd(of: [repos.lib, repos.tools], in: recorder) == Self.relatedCount)
        await host.close()
    }

    // MARK: - One load

    @Test("Two calls of two sessions that reach the same related board at the same time load it one time")
    func sameBoardLoadsOneTime() async throws {
        let repos = try await CrossRepoFixture.ThreeRepos.make(toolsNamed: Self.toolsName, origin: Self.toolsOrigin)
        let recorder = LoadRecorder(waitingInEachLoad: Self.loadDelay)
        let host = Self.makeSlowHost(recordedBy: recorder)
        let app = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let tools = try await host.session(workingDirectory: repos.tools, actor: KanbanHostTests.secondActor)
        let libName = BoardLocatorTests.libName
        async let fromApp = CrossRepoReadTests.board("path", of: libName, on: app)
        async let fromTools = CrossRepoReadTests.board("path", of: libName, on: tools)
        #expect(try await [fromApp, fromTools] == [repos.lib.path, repos.lib.path])
        let libStarts = Self.loadEvents(of: [repos.lib], in: recorder).filter { event in event.kind == .loadDidStart }
        #expect(libStarts.count == 1)
        await host.close()
    }
}
