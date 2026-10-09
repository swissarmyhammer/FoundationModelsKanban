import Testing

/// Tests the documents at the repository root after the removal of the `kanban` command-line tool (^9je3h3z).
///
/// `plan.md` and `README.md` must not name the removed tool or show its shell commands. `README.md` must keep the four
/// filter examples as plain GraphQL documents, each in its own ```` ```graphql ```` code block, because a later task
/// runs each example against the engine.
@Suite("Documentation")
struct DocumentationTests {
    /// The README, relative to the repository root.
    private static let readmePath = "README.md"

    /// The documents that must not name the removed command-line tool, relative to the repository root.
    private static let documentPaths = ["plan.md", readmePath]

    /// A text that names the removed command-line tool: the word `CLI`, or a `kanban` shell command.
    private static let commandLinePattern = #"\bCLI\b|kanban watch|kanban --schema|kanban '"#

    /// The four filter examples of the README, each as the full text of its ```` ```graphql ```` code block. A filter
    /// that starts with `#` follows a `"`, so each raw string has two `#` delimiters.
    private static let filterExamples = [
        ##"{ board { tasks(filter: "#bug && @alice") { edges { node { id title } } } } }"##,
        ##"{ board { history(filter: "~column", first: 5) { txn ops updates { id kind } } } }"##,
        ##"{ board { history(filter: "^01jabcd") { txn actor { name } updates { fields { name before after } } } } }"##,
        ##"subscription { changes(filter: "#bug || ~comment") { txn ops updates { id type kind } } }"##,
    ]

    /// No line of the document names the removed command-line tool.
    @Test("The document does not name the removed command-line tool", arguments: documentPaths)
    func namesNoCommandLineTool(_ path: String) throws {
        let pattern = try Regex(Self.commandLinePattern)
        let namingLines = try RepositoryFile.lines(at: path).filter { $0.contains(pattern) }.map(String.init)

        #expect(namingLines == [], "\(path) must not name the removed command-line tool; found \(namingLines)")
    }

    /// The README has the filter example as the full text of one ```` ```graphql ```` code block.
    @Test("README.md has the filter example in a graphql code block", arguments: filterExamples)
    func readmeHoldsFilterExample(_ example: String) throws {
        let blocks = try Self.graphQLBlocks(in: RepositoryFile.text(at: Self.readmePath))

        #expect(blocks.contains(example), "README.md must have the graphql block \(example); found \(blocks)")
    }

    /// Finds each ```` ```graphql ```` code block of a Markdown text.
    ///
    /// - Parameter markdown: the Markdown text.
    /// - Returns: the text between the opening fence and the closing fence of each block, in document order.
    private static func graphQLBlocks(in markdown: String) -> [String] {
        markdown.matches(of: #/```graphql\n(?<body>[\s\S]*?)\n```/#).map { String($0.body) }
    }
}
