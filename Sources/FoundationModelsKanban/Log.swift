import Logging

/// The loggers of FoundationModelsKanban.
///
/// Each logger is a swift-log `Logger`. The package bootstraps no logging
/// backend. The host application bootstraps one with
/// `LoggingSystem.bootstrap(_:)`, and it selects where the records go.
///
/// Each member makes a new `Logger` at each read. Thus a logger reads the
/// bootstrapped backend at the time of the log call, and an application that
/// bootstraps its backend late still gets the records. A `Logger` that a
/// `static let` keeps would keep the backend of the time of its first read.
public enum Log {
    /// The label of ``kanban``: the module name.
    internal static let kanbanLabel = "FoundationModelsKanban"

    /// The logger of the package.
    public static var kanban: Logger { Logger(label: kanbanLabel) }
}
