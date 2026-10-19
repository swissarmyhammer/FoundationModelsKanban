import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the key of the current board of a session after a `git init` in its bare folder (divergence.md M9): the
/// board takes the git key with no restart, and the next write records the board ID key as a board ID of the board.
///
/// Each test makes the working directory of the session in a ``TemporaryDirectory``, and runs `git init` in it after
/// the session loaded its board. A ``ScanKeyReader`` gives the worktree top and the key, so git runs only to make the
/// repo. No test uses the `.kanban/` directory of this repo.
@Suite("Session: the current board takes the git key after git init in its bare folder", .watcherBudget)
struct SessionGitInitTests {
    @Test("After git init in the bare folder of the working directory, the current board gives the git key")
    func gitInitGivesGitKey() async throws {
        let folder = try await SessionBareFolder.make()
        #expect(try await SessionBareFolder.currentKey(on: folder.session) == folder.gitKey)
        await folder.host.close()
    }

    @Test("After git init in the bare folder of the working directory, the next write records the board ID key")
    func gitInitWriteRecordsBoardID() async throws {
        let folder = try await SessionBareFolder.make()
        let bareID = try #require(ULID(boardKeyText: folder.bareKey))
        let write = #"updateBoard(input: { body: "Plan" }) { name }"#
        try await CrossRepoUndoTests.runWithNoErrors(write, on: folder.session)
        let board = try BoardIDTests.boardNode(inRepoAt: folder.folder)
        #expect(board.ids == [bareID])
        #expect(board.gitKey == folder.gitKey)
        await folder.host.close()
    }
}

// MARK: - Bare folder of a session after git init

/// The working directory of a session, a folder outside git, after a `git init` in it. The session loaded its board
/// before the `git init`, with a board ID as its key.
struct SessionBareFolder {
    /// The temporary directory that holds the working directory.
    let directory: TemporaryDirectory

    /// The working directory of the session. It is a git repo after ``make()``.
    let folder: URL

    /// The host of the session view.
    let host: KanbanHost

    /// The session view of the working directory.
    let session: KanbanGraph

    /// The key of the current board before the `git init`: a board ID.
    let bareKey: String

    /// The key of the current board that git gives after the `git init`.
    let gitKey: String

    /// Makes the working directory, the host, and the session view, and reads the board ID key of the current board.
    /// Then the method runs `git init` in the working directory, and waits until the current board gives the git key
    /// (``ScanRecorder/waitForChange(waitingFor:at:until:)``).
    ///
    /// - Returns: The working directory after the `git init`.
    /// - Throws: An error when a folder, the host, or the view cannot be made, when `git init` fails, or
    ///   ``FolderEventTimeout`` when the current board does not give the git key before the time limit.
    static func make() async throws -> SessionBareFolder {
        let directory = try TemporaryDirectory()
        let folder = try GitSandbox.makeFolder(named: ScanCacheTests.newName, in: directory.url)
        let recorder = ScanRecorder()
        let host = ScanCacheTests.makeHost(reading: ScanKeyReader(), recordedBy: recorder)
        let session = try await host.session(workingDirectory: folder, actor: KanbanHostTests.firstActor)
        let bareKey = try #require(try await currentKey(on: session))
        #expect(ULID(boardKeyText: bareKey) != nil, "The key \(bareKey) of a folder outside git is not a board ID")
        let gitKey = try CrossRepoFixture.keyText(of: ScanCacheTests.newOrigin)
        try await GitSandbox.initializeRepo(at: folder, withIdentity: false)
        let change = "a change after which the current board has the git key"
        try await recorder.waitForChange(waitingFor: change, at: folder) {
            try await currentKey(on: session) == gitKey
        }
        return SessionBareFolder(
            directory: directory,
            folder: folder,
            host: host,
            session: session,
            bareKey: bareKey,
            gitKey: gitKey
        )
    }

    /// Reads the key of the current board of a session.
    ///
    /// - Parameter session: The session view.
    /// - Returns: The key, or `nil` when the response has no key.
    /// - Throws: An error when the response has no board.
    static func currentKey(on session: KanbanGraph) async throws -> String? {
        let response = try await KanbanGraphTests.execute("{ board { key } }", on: session)
        return try KanbanGraphTests.object(named: "board", in: response)["key"] as? String
    }
}
