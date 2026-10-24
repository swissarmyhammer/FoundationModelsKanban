import FoundationModels
import Synchronization

/// One generation call that a ``SpyLanguageModel`` answered.
///
/// A test compares the calls with `==`, so the type holds only the texts that a test of the filter agent reads.
struct SpyModelCall: Sendable, Equatable {
    /// The text of the instructions entry of the transcript of the call, or `nil` when the session has no
    /// instructions.
    let instructions: String?

    /// The text of each prompt entry of the transcript of the call, in order. The first call of a new session has one
    /// prompt entry. A later call of the same session also has the prompt entries of the earlier calls.
    let prompts: [String]
}

/// One answer in the script of a ``SpyLanguageModel``.
enum SpyModelAnswer: Sendable {
    /// Gives this text.
    case text(String)

    /// Throws ``SpyModelError/scriptedFailure``.
    case failure
}

/// The errors that a ``SpyLanguageModel`` throws.
enum SpyModelError: Error, CustomStringConvertible {
    /// The script has a ``SpyModelAnswer/failure`` answer for this call.
    case scriptedFailure

    /// The model got more calls than its script has answers.
    case unscripted(answerCount: Int)

    /// A text that names the error.
    var description: String {
        switch self {
        case .scriptedFailure:
            "The spy model threw its scripted failure."
        case .unscripted(let answerCount):
            "The spy model got more calls than its \(answerCount) scripted answers."
        }
    }
}

/// The script of a ``SpyLanguageModel``, and the record of the generation calls that it answered.
///
/// A class, so that the test reads the same record that the executor writes. A `Mutex`, because the executor writes
/// from the task of the SDK and the test reads from its own task.
final class SpyModelCalls: Sendable {
    /// The answers, in call order.
    private let answers: [SpyModelAnswer]

    /// The calls that the model answered, in order.
    private let calls = Mutex<[SpyModelCall]>([])

    /// Makes the script and an empty record.
    ///
    /// - Parameter answers: The answers, in call order.
    init(answers: [SpyModelAnswer]) {
        self.answers = answers
    }

    /// The calls that the model answered, in order.
    var recorded: [SpyModelCall] {
        calls.withLock { calls in calls }
    }

    /// The number of the generation calls.
    var count: Int {
        recorded.count
    }

    /// Records one generation call, and gives the answer of the script for it.
    ///
    /// - Parameter call: The call.
    /// - Returns: The text of the answer.
    /// - Throws: ``SpyModelError/scriptedFailure`` for a ``SpyModelAnswer/failure`` answer, or
    ///   ``SpyModelError/unscripted(answerCount:)`` when the script has no answer left.
    func answer(_ call: SpyModelCall) throws(SpyModelError) -> String {
        let index = calls.withLock { calls in
            calls.append(call)
            return calls.count - 1
        }
        guard answers.indices.contains(index) else {
            throw .unscripted(answerCount: answers.count)
        }
        switch answers[index] {
        case .text(let text):
            return text
        case .failure:
            throw .scriptedFailure
        }
    }
}

/// A FoundationModels `LanguageModel` test double for the filter agent (divergence.md §17): it answers each generation
/// call from a script, in order, and records each call in ``calls``. A test gives it to the engine as the filter
/// model, and then reads the calls. Thus no test needs a real model.
struct SpyLanguageModel: LanguageModel {
    /// The script and the record of the generation calls.
    let calls: SpyModelCalls

    /// Makes a model that plays a script.
    ///
    /// - Parameter answers: The answers, in call order. The default has no answer: each call throws
    ///   ``SpyModelError/unscripted(answerCount:)``.
    init(answers: [SpyModelAnswer] = []) {
        calls = SpyModelCalls(answers: answers)
    }

    /// The model has no capability: the filter agent asks for text only.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([])
    }

    /// The cache key of the executor: the record of the calls.
    var executorConfiguration: Executor.Configuration {
        Executor.Configuration(calls: calls)
    }

    /// The executor that records each generation call and gives the answer of the script.
    struct Executor: LanguageModelExecutor {
        /// The cache key that the SDK makes and reuses the executor by. The record is compared and hashed by its
        /// identity, so two tests never share an executor.
        struct Configuration: Sendable, Hashable {
            /// The script and the record of the generation calls.
            let calls: SpyModelCalls

            /// Compares the identity of the two records.
            ///
            /// - Parameters:
            ///   - lhs: One configuration.
            ///   - rhs: The other configuration.
            /// - Returns: `true` when the two configurations hold the same record.
            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.calls === rhs.calls
            }

            /// Hashes the identity of the record.
            ///
            /// - Parameter hasher: The hasher to feed.
            func hash(into hasher: inout Hasher) {
                hasher.combine(ObjectIdentifier(calls))
            }
        }

        /// The `LanguageModel` that this executor runs for.
        typealias Model = SpyLanguageModel

        /// The token count of the one text fragment of an answer. The double counts no tokens.
        private static let answerTokenCount = 1

        /// The cache key that the SDK made this executor with.
        private let configuration: Configuration

        /// Stores the cache key.
        ///
        /// - Parameter configuration: The script and the record of the calls.
        /// - Throws: Never. The `LanguageModelExecutor` requirement has `throws`.
        init(configuration: Configuration) throws {
            self.configuration = configuration
        }

        /// Records one generation call, and sends the answer of the script as one text fragment.
        ///
        /// - Parameters:
        ///   - request: The generation request with the full transcript.
        ///   - model: The model that this executor runs for. The executor does not read it.
        ///   - channel: The generation channel that the answer goes into.
        /// - Throws: The ``SpyModelError`` of the script for this call.
        func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: SpyLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            let call = SpyModelCall(
                instructions: Self.instructionsText(in: request.transcript),
                prompts: Self.promptTexts(in: request.transcript)
            )
            let text = try configuration.calls.answer(call)
            await channel.send(.response(action: .appendText(text, tokenCount: Self.answerTokenCount)))
        }

        /// Gives the text of the first instructions entry of a transcript.
        ///
        /// - Parameter transcript: The transcript of a generation call.
        /// - Returns: The text of the entry, or `nil` when there is none.
        private static func instructionsText(in transcript: Transcript) -> String? {
            transcript.lazy.compactMap { entry -> String? in
                guard case .instructions(let instructions) = entry else {
                    return nil
                }
                return text(of: instructions.segments)
            }.first
        }

        /// Gives the text of each prompt entry of a transcript, in order.
        ///
        /// - Parameter transcript: The transcript of a generation call.
        /// - Returns: The text of each prompt entry.
        private static func promptTexts(in transcript: Transcript) -> [String] {
            transcript.compactMap { entry in
                guard case .prompt(let prompt) = entry else {
                    return nil
                }
                return text(of: prompt.segments)
            }
        }

        /// Gives the joined text of the text segments of a transcript entry.
        ///
        /// - Parameter segments: The segments of the entry.
        /// - Returns: The joined text.
        private static func text(of segments: [Transcript.Segment]) -> String {
            segments.compactMap { segment in
                guard case .text(let text) = segment else {
                    return nil
                }
                return text.content
            }.joined()
        }
    }
}
