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

    /// Finds each fenced code block of one language in a Markdown file.
    ///
    /// - Parameters:
    ///   - language: The language of the blocks.
    ///   - path: The path of the Markdown file, relative to the repository root.
    /// - Returns: The text between the opening fence and the closing fence of each block, in document order.
    /// - Throws: An error when the file cannot be read.
    static func codeBlocks(of language: CodeLanguage, at path: String) throws -> [String] {
        try text(at: path)
            .matches(of: #/```(?<language>[a-z]*)\n(?<body>[\s\S]*?)\n```/#)
            .filter { block in block.language == language.rawValue }
            .map { block in String(block.body) }
    }
}

/// The language of a fenced code block of a Markdown file: the info string of its opening fence.
enum CodeLanguage: String {
    /// A GraphQL document: ```` ```graphql ````.
    case graphql

    /// Swift code: ```` ```swift ````.
    case swift

    /// A JavaScript script: ```` ```js ````.
    case js

    /// JSON text: ```` ```json ````.
    case json

    /// Plain text, for example a directory tree: ```` ```text ````.
    case text
}
