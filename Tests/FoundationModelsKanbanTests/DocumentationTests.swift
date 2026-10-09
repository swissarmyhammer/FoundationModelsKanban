import Testing

/// Tests the documents at the repository root after the removal of the `kanban` command-line tool (^9je3h3z).
///
/// `plan.md` and `README.md` must not name the removed tool or show its shell commands. `README.md` must keep the four
/// filter examples as plain GraphQL documents, each in its own ```` ```graphql ```` code block, because a later task
/// runs each example against the engine.
@Suite("Documentation")
struct DocumentationTests {
    /// The README, relative to the repository root.
    static let readmePath = "README.md"

    /// The documents that must not name the removed command-line tool, relative to the repository root.
    private static let documentPaths = ["plan.md", readmePath]

    /// A text that names the removed command-line tool: the word `CLI`, or a `kanban` shell command.
    private static let commandLinePattern = #"\bCLI\b|kanban watch|kanban --schema|kanban '"#

    /// The filter example of the tasks that have the tag `bug` and the assignee `alice`. A filter that starts with `#`
    /// follows a `"`, so each raw string of a filter example has two `#` delimiters.
    static let bugsOfAliceQuery = ##"{ board { tasks(filter: "#bug && @alice") { edges { node { id title } } } } }"##

    /// The filter example of the five newest changes that have a column update.
    static let columnHistoryQuery =
        ##"{ board { history(filter: "~column", first: 5) { txn ops updates { id kind } } } }"##

    /// The filter example of the changes that have an update of one node.
    static let nodeHistoryQuery =
        ##"{ board { history(filter: "^01jabcd") { txn actor { name } updates { fields { name before after } } } } }"##

    /// The filter example of a subscription to the updates of the tasks with the tag `bug` and of each comment.
    static let bugOrCommentSubscription =
        ##"subscription { changes(filter: "#bug || ~comment") { txn ops updates { id type kind } } }"##

    /// The four filter examples of the README, each as the full text of its ```` ```graphql ```` code block.
    private static let filterExamples = [
        bugsOfAliceQuery,
        columnHistoryQuery,
        nodeHistoryQuery,
        bugOrCommentSubscription,
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
        let blocks = try RepositoryFile.codeBlocks(of: .graphql, at: Self.readmePath)

        #expect(blocks.contains(example), "README.md must have the graphql block \(example); found \(blocks)")
    }
}
