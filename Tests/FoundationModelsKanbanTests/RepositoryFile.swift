import Foundation

/// Reads a committed file from the repository root, for the tests that check a file of the repository.
enum RepositoryFile {
    /// The repository root. `#filePath` is `Tests/FoundationModelsKanbanTests/RepositoryFile.swift`, two directories
    /// below the root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/FoundationModelsKanbanTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root

    /// Reads the text of one file.
    ///
    /// - Parameter path: the path of the file, relative to the repository root.
    /// - Returns: the full text of the file.
    /// - Throws: an error when the file cannot be read.
    static func text(at path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Reads the lines of one file.
    ///
    /// - Parameter path: the path of the file, relative to the repository root.
    /// - Returns: each line of the file, with its indent. An empty line is kept.
    /// - Throws: an error when the file cannot be read.
    static func lines(at path: String) throws -> [Substring] {
        try text(at: path).split(separator: "\n", omittingEmptySubsequences: false)
    }
}
