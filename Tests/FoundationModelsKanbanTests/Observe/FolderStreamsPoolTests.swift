import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that a slow FSEvents call of a ``FolderStreams`` holds no thread of the Swift cooperative pool.
///
/// Each FSEvents call is a synchronous message to fseventsd. When a call runs on a thread of the pool and fseventsd is
/// slow to answer, the thread cannot run other tasks. When each thread of the pool waits so, no task of the process
/// can run. The test gives a fake ``FolderEventService`` whose first stream start waits until the test lets it go
/// (``HeldStartService``). The fake makes no FSEvents stream, so the suite needs no slot of the ``WatcherBudget``.
@Suite("Folder streams: a slow FSEvents call holds no thread of the cooperative pool")
struct FolderStreamsPoolTests {
    /// The number of adds and of other tasks for each processor. More tasks than the threads of the pool make each
    /// thread wait, when an add holds its thread.
    static let tasksPerProcessor = 4

    /// The number of adds and of other tasks of the test.
    static var taskCount: Int {
        ProcessInfo.processInfo.activeProcessorCount * tasksPerProcessor
    }

    @Test("Other tasks run to the end while the start of a stream waits for fseventsd")
    func heldStartHoldsNoPoolThread() async throws {
        let service = HeldStartService()
        let streams = FolderStreams(service: service)
        let count = Self.taskCount
        let adds = (0..<count).map { index in
            Task { try await streams.add(Self.makeSink(named: "folder-\(index)")) }
        }
        await service.waitForHeldStart()
        let finished = await withTaskGroup(of: Int.self) { group in
            for index in 0..<count {
                group.addTask { index }
            }
            return await group.reduce(into: Set<Int>()) { finished, index in finished.insert(index) }
        }
        #expect(finished == Set(0..<count))
        service.releaseHeldStart()
        for add in adds {
            try await add.value
        }
        #expect(streams.folderCount == count)
    }

    /// Makes a sink for a folder with a name. The fake service gives no events, so the folder need not exist.
    ///
    /// - Parameter name: The name of the folder, in the temporary directory of the user.
    /// - Returns: The sink.
    static func makeSink(named name: String) -> BatchSink {
        let folder = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        let (_, continuation) = AsyncStream<[URL]>.makeStream()
        return BatchSink(watching: folder, feeding: continuation)
    }
}
