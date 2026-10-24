import Testing

@testable import FoundationModelsKanban

/// Tests the system prompt of the filter agent (divergence.md §17, "A smart prompt"): the resource
/// `FilterAgentPrompt.md` of the package.
///
/// Each example of the prompt is also a test, so it cannot go out of date: the statement parses, and it passes the
/// name check on the sample board of ``FilterEvaluatorTests``, which has each name of the examples.
@Suite("Filter agent prompt")
struct FilterAgentPromptTests {
    /// The path of the resource file, relative to the repository root.
    static let resourcePath = "Sources/FoundationModelsKanban/Resources/FilterAgentPrompt.md"

    /// The English text of the example of ``readerText``.
    static let readerEnglish = "the open bugs"

    /// The filter statement of the example of ``readerText``.
    static let readerFilter = "#bug !#DONE"

    /// A prompt text with one example, a line of prose before it, and an English line with no filter line after it.
    static let readerText = """
        Write one filter.
        \(FilterAgentPrompt.englishLabel)\(readerEnglish)
        \(FilterAgentPrompt.filterLabel)\(readerFilter)
        \(FilterAgentPrompt.englishLabel)a text with no filter line
        """

    /// Reads the examples of the prompt resource.
    ///
    /// - Returns: The examples, in prompt order.
    /// - Throws: An error when the resource cannot be read.
    static func examples() throws -> [FilterAgentPrompt.Example] {
        try FilterAgentPrompt.load().examples
    }

    // MARK: - The resource

    @Test("The prompt loads from the resource bundle of the package, with the text of the resource file")
    func promptLoadsFromBundle() throws {
        #expect(try FilterAgentPrompt.load().text == RepositoryFile.text(at: Self.resourcePath))
    }

    @Test("The virtual tag table of the prompt names each virtual tag, in the order of VirtualTag.allCases")
    func virtualTagTableNamesEachVirtualTag() throws {
        let names = try KanbanSkillTests.virtualTagNames(inTableOf: FilterAgentPrompt.load().text)
        #expect(names == VirtualTag.allCases.map(\.rawValue))
    }

    @Test("The prompt has examples, and each English line of the prompt has a filter line after it")
    func eachEnglishLineHasFilterLine() throws {
        let prompt = try FilterAgentPrompt.load()
        let lines = prompt.text.split(separator: "\n")
        let englishLines = lines.filter { line in line.hasPrefix(FilterAgentPrompt.englishLabel) }
        #expect(!prompt.examples.isEmpty)
        #expect(prompt.examples.count == englishLines.count)
    }

    // MARK: - The example reader

    @Test("The example reader gives each English line that has a filter line after it, and no other line")
    func readerPairsEnglishWithFilter() {
        let expected = [FilterAgentPrompt.Example(english: Self.readerEnglish, filter: Self.readerFilter)]
        #expect(FilterAgentPrompt(text: Self.readerText).examples == expected)
    }

    // MARK: - The examples

    @Test("The statement of the example parses with the filter parser", arguments: try examples())
    func exampleParses(_ example: FilterAgentPrompt.Example) {
        #expect(throws: Never.self) { try FilterExpr(parsing: example.filter) }
    }

    @Test(
        "The statement of the example passes the name check on the sample board, with the parsed filter",
        arguments: try examples()
    )
    func examplePassesNameCheck(_ example: FilterAgentPrompt.Example) throws {
        #expect(try FilterNameCheckTests.sampleCheck(example.filter) == FilterExpr(parsing: example.filter))
    }
}
