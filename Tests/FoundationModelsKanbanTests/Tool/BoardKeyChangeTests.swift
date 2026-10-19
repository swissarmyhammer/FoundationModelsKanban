import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the key change of a loaded board (divergence.md M9): git gives a new key for the board while the board is in
/// memory, for example after a `git init` in the folder of a board outside git, or after a new `origin`. The session
/// takes the new key, and the next write records the key before the change as a name of the board.
///
/// Each test writes the fixture logs of ``KanbanGraphTests`` to a temporary repo, and runs its calls in a commit
/// session of the board. No test runs git.
@Suite("Key change of a loaded board")
struct BoardKeyChangeTests {
    /// The git key that a test gives to the board after the load.
    static let newGitKey = BoardKey(rootCommit: "later")

    /// The board ID that a test gives as the key of the board outside git before the change.
    static let bareID = ULID(timestamp: ReplayTests.date(atStep: CommitTests.callStep))

    /// The write that each test runs after the key change.
    static let writeField = #"updateBoard(input: { body: "Plan" }) { name }"#

    /// Writes the fixture logs to a repo, and loads a commit session of the board with a key.
    ///
    /// - Parameters:
    ///   - key: The key of the board at the load.
    ///   - directory: The temporary repo directory.
    /// - Returns: The session.
    /// - Throws: An error when the fixture cannot be written or loaded.
    static func session(inBoard key: BoardKey, inRepoAt directory: TemporaryDirectory) async throws -> CommitSession {
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        return try await CommitTests.makeSession(of: EventLog(repositoryAt: directory.url), inBoard: key)
    }

    @Test("A key change gives the session the new key and keeps the old key as a former key")
    func keyChangeKeepsFormerKey() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.session(inBoard: KanbanGraphTests.boardKey, inRepoAt: directory)
        session.changeKey(to: Self.newGitKey)
        #expect(session.key == Self.newGitKey)
        #expect(session.formerKeys == [KanbanGraphTests.boardKey])
    }

    @Test("A change to the current key changes nothing")
    func sameKeyChangesNothing() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.session(inBoard: KanbanGraphTests.boardKey, inRepoAt: directory)
        session.changeKey(to: KanbanGraphTests.boardKey)
        #expect(session.key == KanbanGraphTests.boardKey)
        #expect(session.formerKeys.isEmpty)
    }

    @Test("A change back to a former key takes that key out of the former keys")
    func changeBackRemovesFormerKey() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.session(inBoard: KanbanGraphTests.boardKey, inRepoAt: directory)
        session.changeKey(to: Self.newGitKey)
        session.changeKey(to: KanbanGraphTests.boardKey)
        #expect(session.key == KanbanGraphTests.boardKey)
        #expect(session.formerKeys == [Self.newGitKey])
    }

    @Test("takeKey gives a session the key and the former keys of a different session")
    func takeKeyCopiesKeyAndFormerKeys() async throws {
        let directory = try TemporaryDirectory()
        var older = try await Self.session(inBoard: KanbanGraphTests.boardKey, inRepoAt: directory)
        var current = older
        current.changeKey(to: Self.newGitKey)
        older.takeKey(of: current)
        #expect(older.key == Self.newGitKey)
        #expect(older.formerKeys == [KanbanGraphTests.boardKey])
    }

    @Test("The next write after a change of the git key records the former git key as an old name")
    func writeRecordsFormerGitKey() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.session(inBoard: KanbanGraphTests.boardKey, inRepoAt: directory)
        session.changeKey(to: Self.newGitKey)
        try await HistoryTests.run(eachOf: [Self.writeField], in: &session)
        let board = try BoardIDTests.boardNode(inRepoAt: directory.url)
        #expect(board.oldNames == [KanbanGraphTests.boardKey.description])
        #expect(board.gitKey == Self.newGitKey.description)
    }

    @Test("The next write after a git init records the former board ID key as the board ID, and mints no new ID")
    func writeRecordsFormerBoardID() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.session(inBoard: BoardKey(boardID: Self.bareID), inRepoAt: directory)
        session.changeKey(to: Self.newGitKey)
        try await HistoryTests.run(eachOf: [Self.writeField], in: &session)
        let board = try BoardIDTests.boardNode(inRepoAt: directory.url)
        #expect(board.ids == [Self.bareID])
        #expect(board.oldNames.isEmpty)
        #expect(board.gitKey == Self.newGitKey.description)
    }
}
