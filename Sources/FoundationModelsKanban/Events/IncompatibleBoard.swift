import Foundation

// MARK: - Incompatible board

extension EventLog {
    /// The names of the items at the top of `.kanban/` that only the old Rust kanban makes (divergence.md Q6): its
    /// board directory, its view directories, its git config, its search cache, and its undo stack.
    static let rustOnlyNames: Set<String> = [
        "boards",
        "perspectives",
        "views",
        "projects",
        ".gitconfig",
        "search-cache.sqlite3",
        "undo_stack.yaml",
    ]

    /// The start of the name of the log file of a Rust kanban MCP server, for example `mcp.17281.log`.
    static let rustServerLogPrefix = "mcp"

    /// The extension of the log file of a Rust kanban MCP server.
    static let rustServerLogExtension = "log"

    /// The extensions of the entity files that the old Rust kanban writes beside the logs in the node directories,
    /// for example `tasks/<ULID>.md` and `columns/todo.yaml`.
    static let rustEntityExtensions: Set<String> = ["yaml", "md"]

    /// Checks that the `.kanban/` directory is not a board of the old Rust kanban (divergence.md Q6). The check reads
    /// only the names in the directory and in its node directories. It reads no file and changes nothing.
    ///
    /// Each load of a board and each write to a board calls this check first, so that the engine never reads, writes,
    /// or makes a board in a `.kanban/` with Rust files. A repo with no `.kanban/` passes the check.
    ///
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the directory has a Rust-only path: a name of
    ///   ``rustOnlyNames``, an `mcp*.log` file, or a `*.yaml` or `*.md` entity file in a node directory.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a directory is there and cannot be read.
    func checkCompatibility() throws(EventLogError) {
        guard try !hasRustOnlyPath() else {
            throw .incompatibleBoard(directory: directory.path)
        }
    }

    /// Tells if the `.kanban/` directory has a path that only the old Rust kanban makes.
    ///
    /// - Returns: `true` when the directory has a Rust-only path.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory is there and cannot be read.
    private func hasRustOnlyPath() throws(EventLogError) -> Bool {
        if try Self.items(in: directory).contains(where: Self.isRustOnlyTopItem(_:)) {
            return true
        }
        let nodeDirectories = PatchNodeType.allCases.compactMap(\.logDirectoryName).map { name in
            directory.appending(path: name, directoryHint: .isDirectory)
        }
        for nodeDirectory in nodeDirectories {
            if try Self.items(in: nodeDirectory).contains(where: Self.isRustEntityFile(_:)) {
                return true
            }
        }
        return false
    }

    /// Tells if an item at the top of `.kanban/` is a Rust-only item: a name of ``rustOnlyNames``, or the log file of
    /// a Rust kanban MCP server.
    ///
    /// - Parameter item: The item.
    /// - Returns: `true` for a Rust-only item.
    private static func isRustOnlyTopItem(_ item: URL) -> Bool {
        let name = item.lastPathComponent
        let isServerLog = name.hasPrefix(rustServerLogPrefix) && item.pathExtension == rustServerLogExtension
        return rustOnlyNames.contains(name) || isServerLog
    }

    /// Tells if an item of a node directory is an entity file of the old Rust kanban.
    ///
    /// - Parameter item: The item.
    /// - Returns: `true` when the extension of the item is one of ``rustEntityExtensions``.
    private static func isRustEntityFile(_ item: URL) -> Bool {
        rustEntityExtensions.contains(item.pathExtension)
    }
}
