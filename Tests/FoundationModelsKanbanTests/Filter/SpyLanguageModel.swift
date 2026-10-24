import FoundationModels
import Synchronization

/// The record of the generation calls of a ``SpyLanguageModel``.
///
/// A class, so that the test reads the same record that the executor writes. A `Mutex`, because the executor writes
/// from the task of the SDK and the test reads from its own task.
final class SpyModelCalls: Sendable {
    /// The count that each generation call increases.
    private let calls = Mutex(0)

    /// The number of the generation calls.
    var count: Int {
        calls.withLock { count in count }
    }

    /// Records one generation call.
    func record() {
        calls.withLock { count in count += 1 }
    }
}

/// A FoundationModels `LanguageModel` test double for the filter agent (divergence.md §17): it records each generation
/// call in ``calls``, and gives no answer. A test gives it to the engine as the filter model, and then reads the
/// number of calls. Thus no test needs a real model.
struct SpyLanguageModel: LanguageModel {
    /// The record of the generation calls.
    let calls = SpyModelCalls()

    /// The model has no capability: the filter agent asks for text only.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([])
    }

    /// The cache key of the executor: the record of the calls.
    var executorConfiguration: Executor.Configuration {
        Executor.Configuration(calls: calls)
    }

    /// The executor that records each generation call.
    struct Executor: LanguageModelExecutor {
        /// The cache key that the SDK makes and reuses the executor by. The record is compared and hashed by its
        /// identity, so two tests never share an executor.
        struct Configuration: Sendable, Hashable {
            /// The record of the generation calls.
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

        /// The cache key that the SDK made this executor with.
        private let configuration: Configuration

        /// Stores the cache key.
        ///
        /// - Parameter configuration: The record of the calls.
        /// - Throws: Never. The `LanguageModelExecutor` requirement has `throws`.
        init(configuration: Configuration) throws {
            self.configuration = configuration
        }

        /// Records one generation call, and sends no answer.
        ///
        /// - Parameters:
        ///   - request: The generation request. The executor does not read it.
        ///   - model: The model that this executor runs for. The executor does not read it.
        ///   - channel: The generation channel of the call. The executor sends nothing to it.
        func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: SpyLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            configuration.calls.record()
        }
    }
}
