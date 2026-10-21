import Foundation
import Graphiti
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Counts the schema builds that run at the same time, and keeps the highest count.
private final class BuildOverlap: Sendable {
    /// The count of builds that run now, and the highest count so far.
    private let counts = Mutex((running: 0, highest: 0))

    /// The highest count of builds that ran at the same time.
    var highest: Int {
        counts.withLock { counts in counts.highest }
    }

    /// Records that a build started.
    func didStart() {
        counts.withLock { counts in
            counts.running += 1
            counts.highest = max(counts.highest, counts.running)
        }
    }

    /// Records that a build ended.
    func didEnd() {
        counts.withLock { counts in counts.running -= 1 }
    }
}

/// Tests that the kanban GraphQL schemas are built so that parallel callers cannot starve the GraphQL type queues
/// (task ^cnjgjaj).
///
/// GraphQL guards the properties of its types with process-wide dispatch queues, and a schema build reads them with
/// `sync` on the calling thread. Many builds at the same time on the cooperative pool blocked every cooperative thread
/// in those queues. So the schemas with no test extension are built once and shared, and the builds run one at a time.
@Suite("Schema builds: one shared schema, and one build at a time")
struct SchemaBuildConcurrencyTests {
    /// The number of builds with a test extension that start at the same time.
    static let concurrentBuilds = 16

    /// How long the test extension holds its build open, so that builds that are not kept apart overlap.
    static let extensionHold: TimeInterval = 0.005

    /// The highest number of builds that may run at the same time.
    static let buildsAtOnce = 1

    /// Two public schemas with no extension are the same built schema.
    @Test("The public schema with no extension is built one time")
    func publicSchemaIsShared() throws {
        #expect(try PublicSchema().schema === PublicSchema().schema)
    }

    /// Two patch schemas are the same built schema.
    @Test("The patch schema is built one time")
    func patchSchemaIsShared() throws {
        #expect(try PatchSchema().schema === PatchSchema().schema)
    }

    /// A public schema with an extension is its own build, and does not change the shared schema.
    @Test("A public schema with an extension is a separate build")
    func extendedSchemaIsSeparate() throws {
        let extended = try PublicSchema(extendedWith: ResponseWarningsTests.addWarnField)
        let shared = try PublicSchema()
        #expect(extended.schema !== shared.schema)
        #expect(extended.sdl.contains("warn(message: String"))
        #expect(!shared.sdl.contains("warn(message: String"))
    }

    /// Builds with a test extension that start at the same time on the cooperative pool run one at a time.
    @Test("Builds that start at the same time run one at a time")
    func concurrentBuildsRunOneAtATime() async throws {
        let overlap = BuildOverlap()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.concurrentBuilds {
                group.addTask {
                    _ = try PublicSchema(extendedWith: { builder in
                        overlap.didStart()
                        Thread.sleep(forTimeInterval: Self.extensionHold)
                        overlap.didEnd()
                        return builder
                    })
                }
            }
            try await group.waitForAll()
        }
        #expect(overlap.highest == Self.buildsAtOnce)
    }
}
