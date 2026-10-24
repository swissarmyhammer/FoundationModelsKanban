import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the loop of the filter agent (divergence.md §17, "The loop" and "No memory"): the model writes a statement,
/// the engine parses it and runs the name check, and an `INVALID_FILTER` error goes back to the model in the same
/// session, for at most ``FilterAgentLoop/attemptLimit`` attempts.
///
/// The board of the tests is the board of ``FilterVocabularyTests``. The caller actor is `alice`. ``SpyLanguageModel``
/// gives the scripted answers and records each call, so no test needs a real model. Each test compares the full
/// translation and the full list of the calls.
@Suite("Filter agent loop")
struct FilterAgentLoopTests {
    /// The English text of the caller.
    private static let english = "bugs that alice has not finished"

    /// A different English text of the caller, for the second call of the session test.
    private static let otherEnglish = "features in todo"

    /// A statement that parses and names only nodes of the board.
    private static let correctStatement = "#bug @alice !#DONE"

    /// A different statement that parses and names only nodes of the board.
    private static let otherCorrectStatement = "#feature %todo"

    /// An answer that does not parse.
    private static let unparsedAnswer = "bugs of alice"

    /// The first word of ``unparsedAnswer``: the parser stops there.
    private static let unparsedFirstWord = "bugs"

    /// An answer with a tag name that names nothing.
    private static let unknownTagAnswer = "#featur"

    /// An answer with a column name that names nothing.
    private static let unknownColumnAnswer = "%todoo"

    /// The answers that the forgiving read of an answer gives as ``correctStatement``: white space around it, the
    /// filter label of the prompt examples, a code span, a code fence with and with no language, and a code fence that
    /// the answer does not close.
    static let wrappedAnswers = [
        "  \(correctStatement) \n",
        "\(FilterAgentPrompt.filterLabel)\(correctStatement)",
        "`\(correctStatement)`",
        "```\n\(correctStatement)\n```",
        "```text\n\(correctStatement)\n```",
        "```\n\(correctStatement)",
    ]

    // MARK: - Helpers

    /// The `INVALID_FILTER` error of ``unparsedAnswer``.
    ///
    /// - Returns: The error.
    /// - Throws: An error when the first word is not in the answer.
    private static func unparsedError() throws -> KanbanError {
        .invalidFilter(
            filter: unparsedAnswer,
            position: try FilterParserTests.position(of: unparsedFirstWord, in: unparsedAnswer),
            detail: FilterParserTests.notATermDetail(for: unparsedFirstWord),
            example: FilterParserTests.operatorExample
        )
    }

    /// The `INVALID_FILTER` error of ``unknownTagAnswer``.
    ///
    /// - Returns: The error.
    /// - Throws: An error when the atom is not in the answer.
    private static func unknownTagError() throws -> KanbanError {
        try FilterNameCheckTests.unknownName(
            in: unknownTagAnswer,
            at: unknownTagAnswer,
            detail: "no tag named `featur`; the nearest tag is `feature`",
            example: "#feature"
        )
    }

    /// The `INVALID_FILTER` error of ``unknownColumnAnswer``.
    ///
    /// - Returns: The error.
    /// - Throws: An error when the atom is not in the answer.
    private static func unknownColumnError() throws -> KanbanError {
        try FilterNameCheckTests.unknownName(
            in: unknownColumnAnswer,
            at: unknownColumnAnswer,
            detail: "no column named `todoo`; the nearest column is `todo`",
            example: "%todo"
        )
    }

    /// The read view of the board of the tests.
    ///
    /// - Returns: The view.
    /// - Throws: An error when a test ULID is not valid.
    private static func view() throws -> BoardView {
        BoardView(of: try FilterVocabularyTests.board().graph, inBoard: FilterEvaluatorTests.boardKey)
    }

    /// The instructions of each session: the system prompt, a line break, and the vocabulary of the board for `alice`.
    ///
    /// - Returns: The instructions.
    /// - Throws: An error when the prompt resource cannot be read.
    private static func instructions() throws -> String {
        let board = try FilterVocabularyTests.board()
        let vocabulary = FilterVocabularyTests.vocabulary(of: board, for: FilterVocabularyTests.alice)
        return try FilterAgentPrompt.load().text + "\n" + vocabulary
    }

    /// The record of one call of a session with the instructions of the board.
    ///
    /// - Parameter prompts: The prompt entries of the transcript of the call.
    /// - Returns: The call.
    /// - Throws: An error when the prompt resource cannot be read.
    private static func call(prompts: [String]) throws -> SpyModelCall {
        SpyModelCall(instructions: try instructions(), prompts: prompts)
    }

    /// Runs the filter agent on a text, with a model that plays a script.
    ///
    /// - Parameters:
    ///   - text: The text of the caller.
    ///   - model: The filter model.
    /// - Returns: The translation.
    /// - Throws: The ``KanbanError`` of the agent, or an error when a test ULID is not valid.
    private static func translate(
        _ text: String = english,
        with model: SpyLanguageModel
    ) async throws -> FilterTranslation {
        try await FilterAgent(model: model).translate(text, on: view(), for: FilterVocabularyTests.alice)
    }

    // MARK: - The loop

    @Test("A correct statement at once gives attempts 1, in one call with the instructions and the text")
    func correctStatementGivesOneAttempt() async throws {
        let model = SpyLanguageModel(answers: [.text(Self.correctStatement)])
        let translation = try await Self.translate(with: model)
        #expect(translation == FilterTranslation(filter: Self.correctStatement, message: nil, attempts: 1))
        #expect(model.calls.recorded == [try Self.call(prompts: [Self.english])])
    }

    @Test("A parse error and then a correction give attempts 2, and the second prompt is the INVALID_FILTER message")
    func parseErrorThenCorrectionGivesTwoAttempts() async throws {
        let model = SpyLanguageModel(answers: [.text(Self.unparsedAnswer), .text(Self.correctStatement)])
        let translation = try await Self.translate(with: model)
        #expect(translation == FilterTranslation(filter: Self.correctStatement, message: nil, attempts: 2))
        let expectedCalls = [
            try Self.call(prompts: [Self.english]),
            try Self.call(prompts: [Self.english, try Self.unparsedError().message]),
        ]
        #expect(model.calls.recorded == expectedCalls)
    }

    @Test("A name that names nothing and then a correction give attempts 2, and the second prompt is the name error")
    func unknownNameThenCorrectionGivesTwoAttempts() async throws {
        let model = SpyLanguageModel(answers: [.text(Self.unknownTagAnswer), .text(Self.correctStatement)])
        let translation = try await Self.translate(with: model)
        #expect(translation == FilterTranslation(filter: Self.correctStatement, message: nil, attempts: 2))
        let expectedCalls = [
            try Self.call(prompts: [Self.english]),
            try Self.call(prompts: [Self.english, try Self.unknownTagError().message]),
        ]
        #expect(model.calls.recorded == expectedCalls)
    }

    @Test("Three failed attempts give no filter, the last error as the message, attempts 3, and no fourth call")
    func threeFailedAttemptsGiveNoFilter() async throws {
        let answers: [SpyModelAnswer] = [
            .text(Self.unparsedAnswer), .text(Self.unknownTagAnswer), .text(Self.unknownColumnAnswer),
            .text(Self.correctStatement),
        ]
        let model = SpyLanguageModel(answers: answers)
        let translation = try await Self.translate(with: model)
        let lastError = try Self.unknownColumnError().message
        #expect(
            translation == FilterTranslation(filter: nil, message: lastError, attempts: FilterAgentLoop.attemptLimit)
        )
        let firstError = try Self.unparsedError().message
        let secondError = try Self.unknownTagError().message
        let expectedCalls = [
            try Self.call(prompts: [Self.english]),
            try Self.call(prompts: [Self.english, firstError]),
            try Self.call(prompts: [Self.english, firstError, secondError]),
        ]
        #expect(model.calls.recorded == expectedCalls)
    }

    @Test("Two calls of the agent do not share a session: the second call sees only its own text")
    func twoCallsDoNotShareASession() async throws {
        let model = SpyLanguageModel(answers: [.text(Self.correctStatement), .text(Self.otherCorrectStatement)])
        let first = try await Self.translate(with: model)
        let second = try await Self.translate(Self.otherEnglish, with: model)
        #expect(first == FilterTranslation(filter: Self.correctStatement, message: nil, attempts: 1))
        #expect(second == FilterTranslation(filter: Self.otherCorrectStatement, message: nil, attempts: 1))
        let expectedCalls = [try Self.call(prompts: [Self.english]), try Self.call(prompts: [Self.otherEnglish])]
        #expect(model.calls.recorded == expectedCalls)
    }

    @Test("An answer with white space, the filter label, a code span, or a code fence gives the statement in it",
        arguments: wrappedAnswers)
    func wrappedAnswerGivesStatement(answer: String) async throws {
        let model = SpyLanguageModel(answers: [.text(answer)])
        let translation = try await Self.translate(with: model)
        #expect(translation == FilterTranslation(filter: Self.correctStatement, message: nil, attempts: 1))
    }

    // MARK: - An error of the model

    @Test("An error of the model gives FILTER_AGENT_FAILED with the error, and counts no attempt")
    func modelErrorGivesAgentFailed() async throws {
        let model = SpyLanguageModel(answers: [.failure, .text(Self.correctStatement)])
        let reason = String(describing: SpyModelError.scriptedFailure)
        await #expect(throws: KanbanError.filterAgentFailed(reason: reason)) {
            try await Self.translate(with: model)
        }
        #expect(model.calls.recorded == [try Self.call(prompts: [Self.english])])
    }
}
