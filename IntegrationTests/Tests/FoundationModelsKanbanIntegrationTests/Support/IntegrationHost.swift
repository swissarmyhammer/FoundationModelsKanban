import Foundation
import FoundationModelsExtras
import FoundationModelsKanban
import Metal
import Testing

/// The host of the sessions of the integration tests: `KanbanHost.shared`, with the real model as the filter model.
///
/// `KanbanHost.configure(locator:embedder:filterModel:)` must run before the first session loads a board, and a host
/// loads each board one time for the process. The suites of this package run at the same time in one process. Thus
/// each test gets its sessions from ``session(workingDirectory:actor:)``, which configures the shared host one time,
/// before the first session of the process. The configuration gives only the filter model: the locator is the default
/// locator, and the search has no embedder, the same as a host that does not call `configure`.
///
/// The model is `mlx-community/Qwen3.8-27B-mxfp4`, the standard model of the sibling packages. `PooledModel` of
/// FoundationModelsExtras gives it as a FoundationModels `LanguageModel`. The first generation call loads it with
/// `MLXModelLoader` from the Hugging Face cache, and downloads it (about 14 GB) when the cache does not hold it. All
/// the model tests use the one ``model`` of the shared `ModelPool`, so the process loads the model one time.
enum IntegrationHost {
    /// The reference of the real model: Qwen 3.8 27B in the `mxfp4` quantization, the same reference as the Qwen 3.8
    /// tests of FoundationModelsRouter and FoundationModelsMultitool.
    private static let modelReference: ModelRef = "mlx-community/Qwen3.8-27B-mxfp4"

    /// The real model, from the shared pool of the process.
    static let model = PooledModel(ref: modelReference)

    /// The one configuration of `KanbanHost.shared`. The task starts at the first read, and it ends when the host has
    /// the filter model. It is never cancelled: the configuration stays for the whole process.
    private static let configuration = Task {
        await KanbanHost.shared.configure(locator: .default, embedder: nil, filterModel: model)
    }

    /// Makes a session of `KanbanHost.shared`, after the one configuration of the host.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory of the session.
    ///   - actor: The name of the session actor.
    /// - Returns: The session view.
    /// - Throws: The errors of `KanbanHost.session(workingDirectory:actor:)`.
    static func session(workingDirectory: URL, actor: String) async throws -> KanbanGraph {
        await configuration.value
        return try await KanbanHost.shared.session(workingDirectory: workingDirectory, actor: actor)
    }

    /// Requires a Metal device, which MLX needs to run the model.
    ///
    /// As in the sibling packages, a model test does not skip: a machine with no Metal device fails it. A skip gives a
    /// green run that measured nothing.
    ///
    /// - Throws: An `ExpectationFailedError` when the machine has no Metal device.
    static func requireMetalDevice() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "This machine has no Metal device, thus MLX cannot run.")
    }
}
