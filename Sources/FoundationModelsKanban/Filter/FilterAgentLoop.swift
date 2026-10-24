import Foundation
import FoundationModels

/// The loop of the filter agent (divergence.md §17, "The loop" and "No memory"): the filter model writes a statement,
/// and the engine checks it, for at most ``attemptLimit`` attempts.
///
/// Each call makes a new `LanguageModelSession`, so a call does not see the earlier calls. The instructions of the
/// session are the system prompt (``FilterAgentPrompt``) and the vocabulary of the board (``FilterVocabulary``). The
/// first prompt is the text of the caller. The engine parses each answer and runs the name check
/// (``FilterNameCheck``). A parse error or a name that names nothing goes back to the model, in the same session, as
/// the `INVALID_FILTER` message: the position, the specific message, and the corrected example. The first statement
/// that passes the check is the result. After ``attemptLimit`` failed attempts, the result has no filter, and its
/// message is the last error.
///
/// The read of an answer is forgiving: white space around the statement, a code fence, the filter label of the prompt
/// examples, and a code span go away before the check.
struct FilterAgentLoop {
    /// The largest number of statements that the filter model writes for one call.
    static let attemptLimit = 3

    /// The text between the system prompt and the vocabulary of the board in the instructions. The prompt ends with a
    /// line break, so the two parts have a blank line between them.
    private static let instructionsSeparator = "\n"

    /// The filter model.
    private let model: any LanguageModel

    /// The name check of the board of the filter.
    private let check: FilterNameCheck

    /// Makes the loop of one call.
    ///
    /// - Parameters:
    ///   - model: The filter model.
    ///   - check: The name check of the board of the filter.
    init(model: any LanguageModel, check: FilterNameCheck) {
        self.model = model
        self.check = check
    }

    /// Writes a filter statement of the board for a text.
    ///
    /// - Parameters:
    ///   - text: The text, as the caller wrote it.
    ///   - view: The read view of the board of the filter. Its names are the vocabulary of the instructions.
    ///   - caller: The session actor of the call: "me" in the text names this actor.
    /// - Returns: The first statement that passes the check with the number of its attempt, or no filter with the last
    ///   error as the message and ``attemptLimit`` attempts.
    /// - Throws: ``KanbanError/filterAgentFailed(reason:)`` when the prompt resource cannot be read or the model gives
    ///   an error. The error counts no attempt.
    func translate(
        _ text: String,
        on view: BoardView,
        for caller: SessionActor
    ) async throws(KanbanError) -> FilterTranslation {
        let systemPrompt = try await Self.stoppingTheAgent { try FilterAgentPrompt.load() }
        let vocabulary = FilterVocabulary.text(of: view, for: caller)
        let instructions = systemPrompt.text + Self.instructionsSeparator + vocabulary
        let session = LanguageModelSession(model: model, instructions: instructions)
        var prompt = text
        for attempt in 1...Self.attemptLimit {
            let answer = try await Self.stoppingTheAgent { try await session.respond(to: prompt).content }
            let statement = Self.statement(in: answer)
            do throws(KanbanError) {
                try check.check(statement)
                return FilterTranslation(filter: statement, message: nil, attempts: attempt)
            } catch {
                prompt = error.message
            }
        }
        return FilterTranslation(filter: nil, message: prompt, attempts: Self.attemptLimit)
    }

    /// Runs one step of the agent that is not a check of a statement, and gives its error as the error of the agent.
    ///
    /// - Parameter step: The step, for example the read of the prompt resource or one answer of the model.
    /// - Returns: The result of the step.
    /// - Throws: ``KanbanError/filterAgentFailed(reason:)`` with the text of the error of the step.
    private static func stoppingTheAgent<Value>(
        _ step: () async throws -> Value
    ) async throws(KanbanError) -> Value {
        do {
            return try await step()
        } catch {
            throw .filterAgentFailed(reason: String(describing: error))
        }
    }
}

// MARK: - The answer

extension FilterAgentLoop {
    /// The fence of a Markdown code block.
    private static let codeFence = "```"

    /// The mark at the two ends of a Markdown code span.
    private static let codeSpanMark: Character = "`"

    /// The filter label of the prompt examples, with no space after it.
    private static let filterLabel = FilterAgentPrompt.filterLabel.trimmingCharacters(in: .whitespaces)

    /// The steps of the forgiving read of an answer, in order. Each step trims the white space that it leaves.
    private static let answerSteps: [@Sendable (String) -> String] = [
        withoutCodeFence, withoutFilterLabel, withoutCodeSpan,
    ]

    /// Gives the statement in an answer of the model.
    ///
    /// - Parameter answer: The answer, for example ``"Filter: `#bug`"``.
    /// - Returns: The statement, for example `#bug`, with no white space around it.
    static func statement(in answer: String) -> String {
        answerSteps.reduce(trimmed(answer)) { text, step in step(text) }
    }

    /// Removes a code fence around a text.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The lines between the opening fence line, which can name a language, and the closing fence, or the
    ///   text itself when it does not start with a fence.
    private static func withoutCodeFence(_ text: String) -> String {
        guard text.hasPrefix(codeFence), let firstLineEnd = text.firstIndex(where: \.isNewline) else {
            return text
        }
        let body = text[text.index(after: firstLineEnd)...]
        return trimmed(body.hasSuffix(codeFence) ? body.dropLast(codeFence.count) : body)
    }

    /// Removes the filter label at the start of a text.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The text after the label, or the text itself when it does not start with the label.
    private static func withoutFilterLabel(_ text: String) -> String {
        guard text.hasPrefix(filterLabel) else {
            return text
        }
        return trimmed(text.dropFirst(filterLabel.count))
    }

    /// Removes a code span around a text.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The text between the two marks, or the text itself when it is not a code span.
    private static func withoutCodeSpan(_ text: String) -> String {
        guard text.count > 1, text.first == codeSpanMark, text.last == codeSpanMark else {
            return text
        }
        return trimmed(text.dropFirst().dropLast())
    }

    /// Removes the white space and the line breaks at the two ends of a text.
    ///
    /// - Parameter text: The text.
    /// - Returns: The trimmed text.
    private static func trimmed(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
