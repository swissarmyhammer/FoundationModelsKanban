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
/// examples, and a code span go away before the check, in each order. A cancel of the task of the call stops the call
/// with the cancel, not with an error of the agent.
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
    ///   an error. The error counts no attempt. A `CancellationError`, unchanged, when the task of the call is
    ///   cancelled: a cancel is not an error of the model.
    func translate(
        _ text: String,
        on view: BoardView,
        for caller: SessionActor
    ) async throws -> FilterTranslation {
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
    /// The call stops only for the cancel of its own task. When the task is cancelled, the error of the step is the
    /// cancel, also when the model gives a different error for it.
    ///
    /// - Parameter step: The step, for example the read of the prompt resource or one answer of the model.
    /// - Returns: The result of the step.
    /// - Throws: The `CancellationError` of the step, unchanged, or a new `CancellationError`, when the task is
    ///   cancelled. Else ``KanbanError/filterAgentFailed(reason:)`` with the text of the error of the step.
    private static func stoppingTheAgent<Value>(
        _ step: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await step()
        } catch let error where Task.isCancelled {
            throw error as? CancellationError ?? CancellationError()
        } catch {
            throw KanbanError.filterAgentFailed(reason: String(describing: error))
        }
    }
}

// MARK: - The answer

extension FilterAgentLoop {
    /// The mark of a Markdown code span and of a Markdown code fence: a backtick.
    private static let codeMark: Character = "`"

    /// The smallest number of marks of a Markdown code fence.
    private static let fenceMarkMinimum = 3

    /// The filter label of the prompt examples, with no space after it.
    private static let filterLabel = FilterAgentPrompt.filterLabel.trimmingCharacters(in: .whitespaces)

    /// The steps of the forgiving read of an answer, in order. Each step trims the white space that it leaves. The
    /// fence step is before the span step, so that the language of a fence does not stay as a part of the statement.
    private static let answerSteps: [@Sendable (String) -> String] = [
        withoutCodeFence, withoutFilterLabel, withoutCodeSpan,
    ]

    /// Gives the statement in an answer of the model.
    ///
    /// The steps run again until a full round of the steps does not change the text. Thus the wraps can be in each
    /// order, for example a code span around the filter label.
    ///
    /// - Parameter answer: The answer, for example ``"Filter: `#bug`"``.
    /// - Returns: The statement, for example `#bug`, with no white space around it.
    static func statement(in answer: String) -> String {
        let text = trimmed(answer)
        let read = answerSteps.reduce(text) { text, step in step(text) }
        return read == text ? read : statement(in: read)
    }

    /// Removes a code fence around a text.
    ///
    /// A fence starts with a line of ``fenceMarkMinimum`` or more marks, which can name a language. The fence closes
    /// with a run of at least as many marks at the end of the text. A text with no closing fence keeps all of its
    /// lines after the opening line.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The lines between the opening fence line and the closing fence, or the text itself when it does not
    ///   start with a fence line.
    private static func withoutCodeFence(_ text: String) -> String {
        let fenceMarkCount = markCount(of: text, fromEnd: false)
        guard fenceMarkCount >= fenceMarkMinimum, let firstLineEnd = text.firstIndex(where: \.isNewline) else {
            return text
        }
        let body = trimmed(text[text.index(after: firstLineEnd)...])
        let closingMarkCount = markCount(of: body, fromEnd: true)
        return closingMarkCount >= fenceMarkCount ? trimmed(body.dropLast(closingMarkCount)) : body
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
    /// A code span starts and ends with a run of the same number of marks, and its content has no run of that number
    /// of marks. Thus a text of two code spans, for example ``"`#bug` || `#feature`"``, is not one code span.
    ///
    /// - Parameter text: The trimmed text.
    /// - Returns: The content between the two runs of marks, or the text itself when it is not one code span.
    private static func withoutCodeSpan(_ text: String) -> String {
        let spanMarkCount = markCount(of: text, fromEnd: false)
        guard spanMarkCount > 0, markCount(of: text, fromEnd: true) == spanMarkCount else {
            return text
        }
        let content = text.dropFirst(spanMarkCount).dropLast(spanMarkCount)
        let markRuns = content.split { character in character != codeMark }
        guard !content.isEmpty, !markRuns.contains(where: { run in run.count == spanMarkCount }) else {
            return text
        }
        return trimmed(content)
    }

    /// Counts the marks at one end of a text.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - fromEnd: `true` to count the marks at the end of the text, `false` to count the marks at the start.
    /// - Returns: The number of marks in the run of marks at that end of the text.
    private static func markCount(of text: some StringProtocol, fromEnd: Bool) -> Int {
        let isMark = { (character: Character) in character == codeMark }
        return fromEnd ? text.reversed().prefix(while: isMark).count : text.prefix(while: isMark).count
    }

    /// Removes the white space and the line breaks at the two ends of a text.
    ///
    /// - Parameter text: The text.
    /// - Returns: The trimmed text.
    private static func trimmed(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
