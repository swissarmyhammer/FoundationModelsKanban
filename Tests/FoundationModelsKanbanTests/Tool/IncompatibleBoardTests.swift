import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests that the engine refuses a `.kanban/` directory of the old Rust kanban (divergence.md Q6). A `.kanban/` with a
/// Rust-only path is incompatible: the engine reads none of its files, writes none, makes no new board in it, and
/// each call that opens it gives `INCOMPATIBLE_BOARD`. This is true for the current board and for each related board.
///
/// Each fixture is in a temporary folder. No test reads or changes the `.kanban/` directory of this repo.
@Suite("Incompatible Rust board", .watcherBudget)
struct IncompatibleBoardTests {
    /// The text of each file of a Rust fixture.
    static let rustFileText = "rust\n"

    /// One Rust-only path of each kind that the check finds (divergence.md Q6).
    static let rustOnlyPaths: [RustOnlyPath] = [
        .directory("boards"),
        .directory("perspectives"),
        .directory("views"),
        .directory("projects"),
        .file(".gitconfig"),
        .file("search-cache.sqlite3"),
        .file("undo_stack.yaml"),
        .file("mcp.17281.log"),
        .file("columns/todo.yaml"),
        .file("actors/alice.yaml"),
        .file("tags/01M4E3T9Z7XBXV760MFGR5WM9G.yaml"),
        .file("tasks/01M4B3V22A3PCQRESESTYBQ2FH.md"),
    ]

    /// The files of a full Rust board, as the old Rust kanban writes them: a YAML or Markdown entity file beside each
    /// JSONL log, the board log in `boards/`, and the Rust-only files at the top of `.kanban/`.
    static let rustBoardFiles = [
        "boards/board.jsonl",
        "boards/board.yaml",
        "columns/todo.jsonl",
        "columns/todo.yaml",
        "actors/alice.jsonl",
        "actors/alice.yaml",
        "tasks/01M4B3V22A3PCQRESESTYBQ2FH.jsonl",
        "tasks/01M4B3V22A3PCQRESESTYBQ2FH.md",
        ".gitignore",
        "mcp.17281.log",
        "search-cache.sqlite3",
    ]

    /// The empty directories of a full Rust board.
    static let rustBoardDirectories = ["perspectives"]

    /// The name of the file in the repo directory of a related Rust board, outside `.kanban/`.
    static let repoFileName = "README.md"

    // MARK: - Fixture

    /// A Rust-only path in a `.kanban/` directory.
    struct RustOnlyPath: Sendable, CustomTestStringConvertible {
        /// The path relative to the `.kanban/` directory.
        let relativePath: String

        /// `true` for a directory, `false` for a file.
        let isDirectory: Bool

        /// The path, as the test name shows it.
        var testDescription: String {
            relativePath
        }

        /// A Rust-only directory.
        ///
        /// - Parameter path: The path relative to the `.kanban/` directory.
        /// - Returns: The path.
        static func directory(_ path: String) -> RustOnlyPath {
            RustOnlyPath(relativePath: path, isDirectory: true)
        }

        /// A Rust-only file.
        ///
        /// - Parameter path: The path relative to the `.kanban/` directory.
        /// - Returns: The path.
        static func file(_ path: String) -> RustOnlyPath {
            RustOnlyPath(relativePath: path, isDirectory: false)
        }

        /// Makes the path in the `.kanban/` directory of a repo, and each directory above it.
        ///
        /// - Parameter root: The root directory of the repo.
        /// - Throws: An error from `FileManager` when the path cannot be made.
        func make(inRepoAt root: URL) throws {
            let url = EventLog(repositoryAt: root).directory.appending(path: relativePath)
            guard isDirectory else {
                return try IncompatibleBoardTests.writeFile(at: url)
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// The state of one item of a folder: its kind, its size, and its modification time.
    struct ItemState: Hashable {
        /// The file type, for example `NSFileTypeDirectory`.
        let type: String?

        /// The size in bytes.
        let size: Int?

        /// The modification time.
        let modified: Date?
    }

    /// Writes ``rustFileText`` to a file, and makes each directory above it.
    ///
    /// - Parameter file: The file.
    /// - Throws: An error from `FileManager` when the directory or the file cannot be made.
    static func writeFile(at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rustFileText.utf8).write(to: file)
    }

    /// Writes a full Rust board (``rustBoardFiles`` and ``rustBoardDirectories``) to the `.kanban/` directory of a
    /// repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Throws: An error from `FileManager` when a file or a directory cannot be made.
    static func writeRustBoard(inRepoAt root: URL) throws {
        for path in rustBoardFiles {
            try RustOnlyPath.file(path).make(inRepoAt: root)
        }
        for path in rustBoardDirectories {
            try RustOnlyPath.directory(path).make(inRepoAt: root)
        }
    }

    /// Lists each item of a folder and of its subfolders, and the folder itself, with the size and the modification
    /// time of each item.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The state of each item, by its path relative to the folder. The folder itself has the empty path.
    /// - Throws: An error from `FileManager` when the folder or an item cannot be read.
    static func listing(of folder: URL) throws -> [String: ItemState] {
        let paths = [""] + (try FileManager.default.subpathsOfDirectory(atPath: folder.path))
        return Dictionary(
            uniqueKeysWithValues: try paths.map { path in
                let attributes = try FileManager.default.attributesOfItem(atPath: folder.appending(path: path).path)
                let state = ItemState(
                    type: attributes[.type] as? String,
                    size: (attributes[.size] as? NSNumber)?.intValue,
                    modified: attributes[.modificationDate] as? Date
                )
                return (path, state)
            }
        )
    }

    /// Gives the response of a call that the engine stops with `INCOMPATIBLE_BOARD`.
    ///
    /// - Parameter root: The root directory of the repo of the incompatible board, as the engine reads it.
    /// - Returns: The response JSON text.
    /// - Throws: An error from the JSON encoder.
    static func incompatibleResponse(ofRepoAt root: URL) throws -> String {
        try KanbanError.incompatibleBoard(directory: EventLog(repositoryAt: root).directory.path).responseJSON()
    }

    /// The `addTask` mutation with no board field.
    static var addTaskMutation: String {
        AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: ""))
    }

    /// Runs a query and a mutation on a new engine of a repo with no git, and checks that each call gives
    /// `INCOMPATIBLE_BOARD` and that no file of the repo changes.
    ///
    /// - Parameter root: The root directory of the repo. Its `.kanban/` directory has Rust files.
    /// - Throws: An error when the engine cannot start, a call throws, or the repo cannot be read.
    static func expectEachCallRefused(inRepoAt root: URL) async throws {
        let before = try listing(of: root)
        let graph = try KanbanGraphTests.makeGraph(at: root)
        let expected = try incompatibleResponse(ofRepoAt: root)
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph) == expected)
        #expect(try await KanbanGraphTests.execute(addTaskMutation, on: graph) == expected)
        await graph.close()
        #expect(try listing(of: root) == before)
    }

    // MARK: - Check

    @Test("The check of a .kanban/ directory finds each Rust-only path", arguments: rustOnlyPaths)
    func checkFindsRustOnlyPath(path: RustOnlyPath) throws {
        let directory = try TemporaryDirectory()
        try path.make(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        #expect(throws: EventLogError.incompatibleBoard(directory: log.directory.path)) {
            try log.checkCompatibility()
        }
    }

    @Test("The check accepts a Swift board with its git files, its lock file, and a comment log")
    func checkAcceptsSwiftBoard() throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        try log.prepareDirectory()
        try Self.writeFile(at: log.lockFileURL)
        try Self.writeFile(at: log.fileURL(for: .comment(ULID())))
        try log.checkCompatibility()
    }

    @Test("The check accepts a repo with no .kanban/ directory")
    func checkAcceptsMissingDirectory() throws {
        let directory = try TemporaryDirectory()
        try EventLog(repositoryAt: directory.url).checkCompatibility()
    }

    // MARK: - No new board

    @Test("The board directory is not prepared in a .kanban/ with Rust files: no git file is made")
    func prepareRefusesRustBoard() throws {
        let directory = try TemporaryDirectory()
        try RustOnlyPath.file("mcp.17281.log").make(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        let before = try Self.listing(of: directory.url)
        #expect(throws: EventLogError.incompatibleBoard(directory: log.directory.path)) {
            try log.prepareDirectory()
        }
        #expect(try Self.listing(of: directory.url) == before)
    }

    // MARK: - Current board

    @Test(
        "A current board with a Rust-only path gives INCOMPATIBLE_BOARD for a query and a mutation, and changes no file",
        arguments: rustOnlyPaths
    )
    func currentBoardWithRustPathIsRefused(path: RustOnlyPath) async throws {
        let directory = try TemporaryDirectory()
        try path.make(inRepoAt: directory.url)
        try await Self.expectEachCallRefused(inRepoAt: directory.url)
    }

    @Test("A full Rust board as the current board gives INCOMPATIBLE_BOARD for each call, and changes no file")
    func currentRustBoardIsRefused() async throws {
        let directory = try TemporaryDirectory()
        try Self.writeRustBoard(inRepoAt: directory.url)
        try await Self.expectEachCallRefused(inRepoAt: directory.url)
    }

    @Test("A clean Swift board opens as before")
    func swiftBoardOpens() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let response = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph)
        await graph.close()
        #expect(response == KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.taskTitle))
    }

    // MARK: - Related board

    /// Makes two repos side by side, and writes a full Rust board and a file outside `.kanban/` into the related
    /// repo.
    ///
    /// - Returns: The repos.
    /// - Throws: An error when a git command fails, or a file cannot be written.
    static func makeReposWithRustLib() async throws -> CrossRepoFixture.SideBySide {
        let repos = try await CrossRepoFixture.SideBySide.make()
        try writeRustBoard(inRepoAt: repos.lib)
        try writeFile(at: repos.lib.appending(path: repoFileName, directoryHint: .notDirectory))
        return repos
    }

    /// Gives the response of a call that the engine stops at the Rust board of the related repo.
    ///
    /// - Parameter repos: The repos.
    /// - Returns: The response JSON text.
    /// - Throws: An error from the JSON encoder.
    static func libIncompatibleResponse(in repos: CrossRepoFixture.SideBySide) throws -> String {
        try incompatibleResponse(ofRepoAt: repos.lib.resolvingSymlinksInPath())
    }

    @Test("A query of a related Rust board gives INCOMPATIBLE_BOARD, and the call stops")
    func relatedRustBoardStopsQuery() async throws {
        let repos = try await Self.makeReposWithRustLib()
        let before = try Self.listing(of: repos.lib)
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let query = #"{ board { name } related: board(id: "\#(try CrossRepoWriteTests.libKey())") { name } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        await graph.close()
        #expect(response == (try Self.libIncompatibleResponse(in: repos)))
        #expect(try Self.listing(of: repos.lib) == before)
    }

    @Test("addTask with the board field set to a related Rust board gives INCOMPATIBLE_BOARD, and writes nothing")
    func boardFieldOnRustBoardWritesNothing() async throws {
        let repos = try await Self.makeReposWithRustLib()
        let before = try Self.listing(of: repos.lib)
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let field = AddUpdateTaskTests.addTask(with: CrossRepoWriteTests.boardField(try CrossRepoWriteTests.libKey()))
        let response = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: field), on: graph)
        await graph.close()
        #expect(response == (try Self.libIncompatibleResponse(in: repos)))
        #expect(try Self.listing(of: repos.lib) == before)
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: repos.app))
    }
}
