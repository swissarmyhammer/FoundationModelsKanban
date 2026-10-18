import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsKanban

/// Tests the `kanban` skill for the Swift kanban (^xa1whj1).
///
/// The skill is in the `../skills` repo, at `skills/kanban/SKILL.md`. That repo is not always next to this repo (for
/// example on CI). Thus this repo keeps a copy of the skill at ``skillPath``, and the tests read the copy:
///
/// - Each ```` ```js ```` block of the skill is a code-mode script that calls `tools.kanban(...)`. The next block is a
///   ```` ```json ```` block with the result of the script. The tests run each script in skill order, on one board in
///   a temporary git repo with no remote, and compare each result with its block.
/// - When `../skills` is next to this repo, a test checks that its skill file is the same text as the copy. When the
///   file is not there, a condition trait disables the test, and the test report shows it as skipped.
@Suite("Kanban skill: the examples run against the Swift tool", .watcherBudget)
struct KanbanSkillTests {
    /// The copy of the skill in this repo, relative to the repository root.
    static let skillPath = "Documentation/kanban/SKILL.md"

    /// The skill file in the `../skills` repo: the repo `skills` next to this repo.
    private static let skillsRepoFile = RepositoryFile.root
        .deletingLastPathComponent()
        .appending(path: "skills/skills/kanban/SKILL.md")

    /// The keys of the frontmatter of a skill, in order, as `skills/commit/SKILL.md` of the `../skills` repo has
    /// them. The kanban skill has no `agent` key, because no agent runs it.
    private static let frontmatterKeys = ["name", "description", "license", "compatibility", "metadata"]

    /// The keys of the `metadata` object of the frontmatter, in order.
    private static let metadataKeys = ["author", "version"]

    /// The `name` line of the frontmatter.
    private static let nameLine = "name: kanban"

    /// The line that opens and closes the frontmatter.
    private static let frontmatterFence = "---"

    /// The indent of a key of the `metadata` object of the frontmatter.
    private static let metadataIndent = "  "

    /// The heading of the section of the skill that lists the virtual tags.
    private static let virtualTagHeading = "## Virtual tags"

    /// The start of each level-two heading of the skill.
    private static let sectionStart = "\n## "

    /// The name that is not a virtual tag in the Swift kanban (divergence.md Q1, C1).
    private static let blockingName = "BLOCKING"

    /// The words that each line that names ``blockingName`` must have: BLOCKING is an ordinary tag.
    private static let ordinaryTagWords = "ordinary tag"

    /// The texts that start a Stencil tag. The `../skills` repo renders each skill as a Stencil template, so a code
    /// block must not have one of them.
    private static let stencilTagStarts = ["{{", "{%", "{#"]

    /// The language of a code-mode script block of the skill.
    private static let scriptLanguage = CodeLanguage.js.rawValue

    /// The language of a result block of the skill.
    private static let resultLanguage = CodeLanguage.json.rawValue

    // MARK: - Helpers

    /// One code-mode script of the skill and the result that the skill shows for it.
    struct Example {
        /// The JavaScript of the ```` ```js ```` block.
        let script: String

        /// The JSON text of the ```` ```json ```` block after the script, or `nil` when the next block is not a
        /// ```` ```json ```` block.
        let result: String?
    }

    /// The `kanban` tool of the examples. It runs each call on a ``KanbanTool`` and keeps each response.
    private struct RecordingKanbanTool: Tool {
        /// The name of the tool: the name of ``KanbanTool``, so that a script calls `tools.kanban(...)`.
        let name: String

        /// The description of ``KanbanTool``.
        let description: String

        /// The tool that runs each call.
        let tool: KanbanTool

        /// The responses of the calls, in call order.
        let responses: ResponseRecord

        /// The arguments of ``KanbanTool``.
        var parameters: GenerationSchema {
            tool.parameters
        }

        /// Makes the tool over an engine.
        ///
        /// - Parameters:
        ///   - graph: The engine.
        ///   - responses: The record that gets each response.
        init(graph: KanbanGraph, responses: ResponseRecord) {
            tool = KanbanTool(graph: graph)
            name = tool.name
            description = tool.description
            self.responses = responses
        }

        /// Runs one call on ``tool``, and adds the response to ``responses``.
        ///
        /// - Parameter arguments: The arguments of the call.
        /// - Returns: The response of ``KanbanTool``.
        /// - Throws: The error of ``KanbanTool``.
        func call(arguments: KanbanArguments) async throws -> String {
            let response = try await tool.call(arguments: arguments)
            await responses.add(response)
            return response
        }
    }

    /// The responses of the `kanban` calls of the examples.
    private actor ResponseRecord {
        /// The responses, in call order.
        private(set) var list: [String] = []

        /// Adds one response.
        ///
        /// - Parameter response: The response JSON text.
        func add(_ response: String) {
            list.append(response)
        }
    }

    /// The outcome of a run of all examples on one board.
    private struct Run {
        /// The result of each script, as JSON text with sorted keys, in skill order.
        let results: [String]

        /// The response of each `kanban` call of the scripts, in call order.
        let responses: [String]
    }

    /// Reads the text of the copy of the skill.
    ///
    /// - Returns: The full text.
    /// - Throws: An error when the file cannot be read.
    private static func skillText() throws -> String {
        try RepositoryFile.text(at: skillPath)
    }

    /// Reads each code-mode example of the skill, with the result block after it.
    ///
    /// - Returns: The examples, in skill order.
    /// - Throws: An error when the file cannot be read.
    static func examples() throws -> [Example] {
        let blocks = try RepositoryFile.fencedBlocks(at: skillPath)
        return blocks.indices.filter { index in blocks[index].language == scriptLanguage }.map { index in
            let next = blocks.indices.contains(index + 1) ? blocks[index + 1] : nil
            return Example(script: blocks[index].body, result: next?.language == resultLanguage ? next?.body : nil)
        }
    }

    /// Reads the lines of the frontmatter of the skill: the lines between the first two ``frontmatterFence`` lines.
    ///
    /// - Returns: The lines, or no line when the skill does not start with a frontmatter.
    /// - Throws: An error when the file cannot be read.
    private static func frontmatterLines() throws -> [Substring] {
        let lines = try RepositoryFile.lines(at: skillPath)
        guard lines.first == Substring(frontmatterFence) else {
            return []
        }
        return Array(lines.dropFirst().prefix { line in line != frontmatterFence })
    }

    /// Gives the key of a frontmatter line: the text before the first `:`, without the indent.
    ///
    /// - Parameter line: The frontmatter line.
    /// - Returns: The key.
    private static func key(of line: Substring) -> String {
        String(line.prefix { character in character != ":" }).trimmingCharacters(in: .whitespaces)
    }

    /// Runs each example of the skill, in skill order, on one new board.
    ///
    /// A result that is not JSON, for example the error text of a script that throws, stays as it is, so that the
    /// failure shows it.
    ///
    /// - Returns: The result of each script and the response of each call.
    /// - Throws: An error when the skill cannot be read, when the board cannot be made, or when `runCode` throws.
    private static func runExamples() async throws -> Run {
        let board = try await ReadmeExamplesTests.ExampleBoard()
        let responses = ResponseRecord()
        let tool = RecordingKanbanTool(graph: board.graph, responses: responses)
        var results: [String] = []
        for example in try examples() {
            let output = try await CodeModeTests.run(example.script, with: tool)
            results.append((try? ReadmeExamplesTests.sortedJSON(output)) ?? output)
        }
        await board.graph.close()
        return Run(results: results, responses: await responses.list)
    }

    // MARK: - The file

    @Test("The skill has the frontmatter keys of the commit skill, and the name kanban")
    func frontmatterHasCommitSkillKeys() throws {
        let lines = try Self.frontmatterLines()
        let topKeys = lines.filter { line in !line.hasPrefix(Self.metadataIndent) }.map(Self.key(of:))
        let metadata = lines.filter { line in line.hasPrefix(Self.metadataIndent) }.map(Self.key(of:))
        #expect(topKeys == Self.frontmatterKeys)
        #expect(metadata == Self.metadataKeys)
        #expect(lines.first == Substring(Self.nameLine))
    }

    @Test("The skill has no op-style JSON call")
    func hasNoOpStyleCall() throws {
        let calls = try Self.skillText().matches(of: #/\{\s*"op"\s*:/#).map { call in String(call.output) }
        #expect(calls == [])
    }

    @Test("The virtual tag table of the skill names each virtual tag of the Swift kanban")
    func virtualTagTableNamesEachVirtualTag() throws {
        let text = try Self.skillText()
        let heading = Self.virtualTagHeading
        let section = try #require(text.range(of: heading), "the skill must have \(heading)")
        let rest = text[section.upperBound...]
        let body = rest.range(of: Self.sectionStart).map { end in rest[..<end.lowerBound] } ?? rest
        let tags = body.matches(of: #/(?m)^\| `(?<tag>[A-Z]+)` \|/#).map { row in String(row.tag) }
        #expect(tags == VirtualTag.allCases.map(\.rawValue))
    }

    @Test("Each line of the skill that names BLOCKING says that it is an ordinary tag")
    func blockingIsOnlyAnOrdinaryTag() throws {
        let lines = try RepositoryFile.lines(at: Self.skillPath).filter { line in line.contains(Self.blockingName) }
        #expect(!lines.isEmpty, "the skill must say that \(Self.blockingName) is an ordinary tag")
        #expect(lines.allSatisfy { line in line.contains(Self.ordinaryTagWords) }, "\(lines)")
    }

    @Test("No code block of the skill has the start of a Stencil tag")
    func codeBlocksHaveNoStencilTag() throws {
        let blocks = try RepositoryFile.fencedBlocks(at: Self.skillPath).map(\.body)
        let tagged = blocks.filter { block in Self.stencilTagStarts.contains { start in block.contains(start) } }
        #expect(tagged == [])
    }

    @Test("Each js block of the skill has a json block with its result after it")
    func eachScriptHasResultBlock() throws {
        let examples = try Self.examples()
        #expect(!examples.isEmpty)
        #expect(examples.filter { example in example.result == nil }.map(\.script) == [])
    }

    @Test(
        "The skill file of ../skills is the same text as the copy in this repo",
        .enabled(
            if: FileManager.default.fileExists(atPath: KanbanSkillTests.skillsRepoFile.path),
            "the ../skills repo is not next to this repo, so there is no skill file to compare"
        )
    )
    func copyIsSkillsRepoFile() throws {
        let copy = try Self.skillText()
        let skillsRepoText = try String(contentsOf: Self.skillsRepoFile, encoding: .utf8)
        #expect(skillsRepoText == copy, "\(Self.skillsRepoFile.path) must be the same as \(Self.skillPath)")
    }

    // MARK: - The examples

    @Test("Each example script gives the result that the skill shows, on a board in a git repo with no remote")
    func eachExampleGivesItsResult() async throws {
        let examples = try Self.examples()
        let run = try await Self.runExamples()
        for (example, result) in zip(examples, run.results) {
            #expect(result == example.result, "the script\n\(example.script)\ngives\n\(result)")
        }
        #expect(run.results.count == examples.count)
    }

    @Test("Each call of the examples uses the canonical names: no response has extensions.rewrites")
    func examplesUseCanonicalNames() async throws {
        let run = try await Self.runExamples()
        let rewritten = try run.responses.filter { response in
            (try KanbanGraphTests.object(of: response)["extensions"] as? [String: Any])?["rewrites"] != nil
        }
        #expect(!run.responses.isEmpty)
        #expect(rewritten == [])
    }
}
