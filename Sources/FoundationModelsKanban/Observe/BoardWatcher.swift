import Foundation

/// Watches one directory, and each directory in it, with file-level FSEvents events (plan.md §5.6, watcher).
///
/// The watcher starts no FSEvents stream of its own. It adds its directory to the ``FolderStreams`` of its host, so
/// one stream serves each watcher of the host (divergence.md §16).
///
/// FSEvents reports events in groups. The watcher gives the changed paths of each group in its directory as one batch
/// in ``batches``. When FSEvents tells that it dropped events, or that the receiver must scan the directory again, the
/// batch also holds the watched directory itself. The receiver then compares each file of the directory.
///
/// The watcher runs until ``stop()``, or until nothing holds the watcher. Then ``batches`` ends.
actor BoardWatcher {
    /// The changed paths of each group of events, in the order of the groups. The stream ends when the watcher stops.
    nonisolated let batches: AsyncStream<[URL]>

    /// The FSEvents stream of the host that watches the directory. A moved watcher of a board uses the same streams.
    nonisolated let folderStreams: FolderStreams

    /// Gives each group of events to ``batches``.
    private let sink: BatchSink

    /// `true` until ``stop()``: the FSEvents stream watches the directory and can give a batch. A test reads it to
    /// prove that a watcher stopped, because a batch that does not come has no time after which it cannot come.
    private(set) var isRunning = true

    /// Starts to watch a directory. Only the events after the start come in ``batches``.
    ///
    /// - Parameters:
    ///   - directory: The directory. It must exist.
    ///   - folderStreams: The FSEvents stream of the host.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream.
    init(watching directory: URL, in folderStreams: FolderStreams) async throws(BoardWatcherError) {
        let (batches, continuation) = AsyncStream<[URL]>.makeStream()
        let sink = BatchSink(watching: directory, feeding: continuation)
        try await folderStreams.add(sink)
        self.batches = batches
        self.folderStreams = folderStreams
        self.sink = sink
    }

    /// Gives one batch that holds the watched directory, the same as a batch of lost events. The receiver then
    /// compares each file of the directory. After ``stop()``, the call gives nothing.
    ///
    /// FSEvents gives a folder only the events after the start of a stream that watches the folder. Thus a change
    /// between a read of the files and the start of the watcher gives no event. A caller that read the files before
    /// the start calls this one time after the start, so that the compare finds that change: a board engine after its
    /// load, and a host after it records what git told about a folder that a path ref named.
    nonisolated func compareEachFile() {
        sink.receive([], losingEvents: true)
    }

    /// Stops the watcher and ends ``batches``. After the call returns, the FSEvents stream of the host does not watch
    /// the directory for this watcher any more. A second call does nothing.
    func stop() async {
        guard isRunning else {
            return
        }
        isRunning = false
        await folderStreams.remove(sink)
        sink.finish()
    }

    isolated deinit {
        guard isRunning else {
            return
        }
        folderStreams.removeWithoutWait(sink)
        sink.finish()
    }
}

// MARK: - Sink

/// Gives the paths of each group of events in one directory as one batch.
final class BatchSink: Sendable {
    /// The watched directory.
    let directory: URL

    /// The continuation of the batches of the watcher.
    private let continuation: AsyncStream<[URL]>.Continuation

    /// Makes the sink of a watcher.
    ///
    /// - Parameters:
    ///   - directory: The watched directory.
    ///   - continuation: The continuation of the batches of the watcher.
    init(watching directory: URL, feeding continuation: AsyncStream<[URL]>.Continuation) {
        self.directory = directory
        self.continuation = continuation
    }

    /// Gives the paths of one group of events in the directory as one batch. When events of the directory are lost,
    /// the batch also holds the watched directory, so that the receiver compares each file of the directory.
    ///
    /// - Parameters:
    ///   - paths: The changed paths in the directory.
    ///   - isLost: `true` when FSEvents tells that events of the directory are lost.
    func receive(_ paths: [String], losingEvents isLost: Bool) {
        let changed = paths.map { path in URL(filePath: path) }
        continuation.yield(isLost ? changed + [directory] : changed)
    }

    /// Ends the batches.
    func finish() {
        continuation.finish()
    }
}

/// An error of a ``BoardWatcher``.
enum BoardWatcherError: Error, Hashable, Sendable {
    /// FSEvents cannot make or start the stream of a directory.
    case streamNotStarted(path: String)
}
