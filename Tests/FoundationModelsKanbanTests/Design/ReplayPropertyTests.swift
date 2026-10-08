import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// The tests of plan.md §11 that check the whole design, not one feature: replay, merge, portability, and schema
/// change. The suites of this namespace have `Design` in their test ids, so `swift test --filter Design` runs them.
enum Design {}

extension Design {
    /// Tests replay against the live writes (plan.md §5.3, §5.4, §11): random sequences of public mutation calls run
    /// in a commit session of the fixture board. After each sequence, the logs on disk must give the same graph as
    /// the live graph, and each line must be a `patch` event with only the parts that change its node.
    ///
    /// The sequences come from one fixed seed, so each run tests the same calls. The sequences run at the same time,
    /// each one in its own temporary repo.
    @Suite("Design: replay of random public mutation sequences")
    struct ReplayPropertyTests {
        /// The seed of the generator that gives the seed of each sequence.
        static let seed: UInt64 = 0x5EED_4E91

        /// The number of random sequences that each property test runs.
        static let sequenceCount = 200

        /// The number of calls in one sequence, after the base setup.
        static let callCount = 6

        /// The largest number of sequences that run at the same time.
        static let parallelSequenceCount = 8

        /// The titles that a call gives to a task.
        static let titles = [KanbanGraphTests.taskTitle, UndoTests.firstTitle, UndoTests.secondTitle]

        /// The bodies that a call gives to a task. The last body has a checked item and a tag marker.
        static let bodies = [
            UndoTests.bodyLines,
            UndoTests.lines(UndoTests.bodyLines, changing: 1, to: UndoTests.changedLine),
            ["- [x] read the grammar", "fix #\(AddUpdateTaskTests.markerSlug)"],
        ]

        /// The column slugs that `moveTask` names. The last slug names no column, so the move makes it.
        static let columns = [
            TaskOperationTests.todoSlug,
            TaskOperationTests.doneSlug,
            TaskOperationTests.newColumnSlug,
        ]

        /// The tag slugs that a call names. The base setup adds only `bug`.
        static let tags = [TagMutationTests.bug, TagMutationTests.defect, TaskOperationTests.feature]

        /// The actor slugs that `assignTask` and `unassignTask` name.
        static let actors = [AddUpdateTaskTests.alice, AddUpdateTaskTests.bob]

        // MARK: - Runner

        /// Runs ``sequenceCount`` random sequences, each in its own temporary repo, and checks the board after each
        /// sequence.
        ///
        /// - Parameter check: Checks the commit session after the calls of one sequence. It also gets the generator
        ///   of the sequence, for more random values.
        /// - Returns: The name of each public mutation that wrote at least one event, in all sequences.
        static func runSequences(
            checking check: @escaping @Sendable (CommitSession, inout SplitMix64) async throws -> Void
        ) async throws -> Set<String> {
            var generator = SplitMix64(seed: seed)
            let seeds = (0..<sequenceCount).map { _ in generator.next() }
            return try await withThrowingTaskGroup(of: Set<String>.self) { group in
                var written: Set<String> = []
                for (index, sequenceSeed) in seeds.enumerated() {
                    if index >= parallelSequenceCount, let operations = try await group.next() {
                        written.formUnion(operations)
                    }
                    group.addTask { try await runSequence(seededWith: sequenceSeed, checking: check) }
                }
                for try await operations in group {
                    written.formUnion(operations)
                }
                return written
            }
        }

        /// Runs one random sequence in a new temporary repo: the base setup of ``ChangeBuilderTests``, then
        /// ``callCount`` random calls. A call that a graph rule refuses writes nothing, and the sequence goes on.
        ///
        /// - Parameters:
        ///   - sequenceSeed: The seed of the generator of the sequence.
        ///   - check: Checks the commit session after the calls.
        /// - Returns: The name of each public mutation that wrote at least one event in the sequence.
        static func runSequence(
            seededWith sequenceSeed: UInt64,
            checking check: @Sendable (CommitSession, inout SplitMix64) async throws -> Void
        ) async throws -> Set<String> {
            let directory = try TemporaryDirectory()
            // The repo stays on disk until the check ends.
            defer { withExtendedLifetime(directory) {} }
            var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
            var generator = SplitMix64(seed: sequenceSeed)
            for _ in 0..<callCount {
                let call = RandomCall.allCases[Int.random(in: RandomCall.allCases.indices, using: &generator)]
                let field = call.field(choosingFrom: tasks(of: session), using: &generator)
                _ = try await ColumnActorTests.result(of: AddUpdateTaskTests.mutation(of: field), in: &session)
            }
            try await check(session, &generator)
            return Set(session.live.events.flatMap(\.ops))
        }

        /// Gives the tasks of the live graph of a session, live or tombstoned, in ULID order.
        ///
        /// - Parameter session: The commit session.
        /// - Returns: The ULID of each task.
        static func tasks(of session: CommitSession) -> [ULID] {
            let graph = session.live.graph
            return graph.allSlots.compactMap { slot in graph.node(at: slot, as: TaskNode.self)?.id }.sorted()
        }

        /// Gives one item of a list at random.
        ///
        /// - Parameters:
        ///   - items: The list. It must not be empty.
        ///   - generator: The source of random numbers.
        /// - Returns: The item.
        static func pick<Item>(from items: [Item], using generator: inout SplitMix64) -> Item {
            items[Int.random(in: items.indices, using: &generator)]
        }

        // MARK: - Checks

        /// Expects that each line of each log of a board is a `patch` event, and that each patch holds only the parts
        /// that change its node after the earlier events of the node (plan.md §5.4 step 4.2).
        ///
        /// - Parameter log: The event log of the board.
        static func expectOnlyChangingPatches(in log: EventLog) throws {
            for ref in try log.nodeFileSignatures().keys {
                let text = try String(contentsOf: log.fileURL(for: ref), encoding: .utf8)
                let lines = text.split(separator: EventLog.lineBreak)
                let events = try lines.map { line in try Event(parsing: String(line)) }
                    .sorted { lhs, rhs in lhs.id < rhs.id }
                for (index, event) in events.enumerated() {
                    #expect(event.query == Event.patchQuery, "\(ref) \(event.id)")
                    expectChangesOnly(event, after: Array(events[..<index]))
                }
            }
        }

        /// Expects that each part of the patch of an event changes its node: a `set` gives a new value, an `unset`
        /// clears a value, an `add` adds a member, a `remove` removes a member, a `delete` changes the tombstone
        /// state, and an `edit` changes the body. The check folds the events itself, so it does not use the code that
        /// a call uses to drop the parts that change nothing.
        ///
        /// - Parameters:
        ///   - event: The event.
        ///   - earlier: The events of the node before the event, in replay order.
        static func expectChangesOnly(_ event: Event, after earlier: [Event]) {
            let patch = event.patch
            let before = NodeSnapshot(folding: earlier, for: patch.node)
            let values = before?.properties.values ?? [:]
            let members = before?.properties.members ?? [:]
            let comment = Comment(rawValue: "\(patch.node) \(event.id) ops: \(event.ops)")
            for (name, value) in patch.set {
                #expect(values[name] != value, comment)
            }
            for name in patch.unset {
                #expect(values[name] != nil, comment)
            }
            for (name, refs) in patch.add {
                #expect(refs.allSatisfy { ref in !(members[name] ?? []).contains(ref) }, comment)
            }
            for (name, refs) in patch.remove {
                #expect(refs.allSatisfy { ref in (members[name] ?? []).contains(ref) }, comment)
            }
            if let delete = patch.delete {
                #expect(delete != (before?.isDeleted ?? false), comment)
            }
            if patch.edit != nil {
                #expect(NodeSnapshot(folding: earlier + [event], for: patch.node)?.body != before?.body, comment)
            }
        }

        /// Writes the lines of each log of a board again, in a random order.
        ///
        /// - Parameters:
        ///   - log: The event log of the board.
        ///   - generator: The source of random numbers.
        static func shuffleLines(of log: EventLog, using generator: inout SplitMix64) throws {
            for ref in try log.nodeFileSignatures().keys {
                let file = log.fileURL(for: ref)
                let lines = try String(contentsOf: file, encoding: .utf8).split(separator: EventLog.lineBreak)
                let shuffled = lines.shuffled(using: &generator).joined(separator: EventLog.lineBreak)
                try (shuffled + EventLog.lineBreak).write(to: file, atomically: true, encoding: .utf8)
            }
        }

        // MARK: - Tests

        @Test("After each random sequence of public mutations, a fresh load of the logs equals the live graph")
        func freshLoadEqualsLiveGraph() async throws {
            let written = try await Self.runSequences { session, _ in
                try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: session.live.log)
            }
            // The property says something only when each kind of call wrote in some sequence.
            #expect(written.isSuperset(of: RandomCall.allCases.map(\.mutationName)))
        }

        @Test("Each log line of a random sequence is a patch event with only the parts that change its node")
        func eachLineIsChangingPatch() async throws {
            let written = try await Self.runSequences { session, _ in
                try Self.expectOnlyChangingPatches(in: session.live.log)
            }
            #expect(written.isSuperset(of: RandomCall.allCases.map(\.mutationName)))
        }

        @Test("The lines of each log of a random sequence in a random order load to the same graph and event list")
        func shuffledLinesLoadTheSame() async throws {
            _ = try await Self.runSequences { session, generator in
                let log = session.live.log
                let before = try await BoardLoader(reading: log).load()
                try Self.shuffleLines(of: log, using: &generator)
                let after = try await BoardLoader(reading: log).load()
                let canonical = LiveGraphApplyTests.canonicalNodes
                #expect(canonical(after.graph) == canonical(before.graph))
                #expect(after.events == before.events)
            }
        }
    }
}

// MARK: - Random calls

extension Design.ReplayPropertyTests {
    /// One kind of public mutation call that a random sequence makes.
    enum RandomCall: CaseIterable {
        /// `addTask`, with no other input, with a tag, or with a dependency.
        case addTask

        /// `updateTask` with a new title.
        case updateTitle

        /// `updateTask` with a new body.
        case updateBody

        /// `updateTask` with a new list of dependencies.
        case updateDependencies

        /// `moveTask` to a column.
        case moveTask

        /// `completeTask`.
        case completeTask

        /// `assignTask` with an actor.
        case assignTask

        /// `unassignTask` with an actor.
        case unassignTask

        /// `tagTask` with a tag.
        case tagTask

        /// `untagTask` with a tag.
        case untagTask

        /// `deleteTask`.
        case deleteTask

        /// `undeleteTask`.
        case undeleteTask

        /// `addComment` on a task.
        case addComment

        /// `renameTag` from one tag to a different tag.
        case renameTag

        /// `undo` of the newest transaction of the session actor.
        case undo

        /// `redo` of the newest undo of the session actor.
        case redo

        /// The name of the public mutation of the call.
        var mutationName: String {
            switch self {
            case .addTask: MutationName.addTask
            case .updateTitle, .updateBody, .updateDependencies: MutationName.updateTask
            case .moveTask: MutationName.moveTask
            case .completeTask: MutationName.completeTask
            case .assignTask: MutationName.assignTask
            case .unassignTask: MutationName.unassignTask
            case .tagTask: MutationName.tagTask
            case .untagTask: MutationName.untagTask
            case .deleteTask: MutationName.deleteTask
            case .undeleteTask: MutationName.undeleteTask
            case .addComment: MutationName.addComment
            case .renameTag: MutationName.renameTag
            case .undo: MutationName.undo
            case .redo: MutationName.redo
            }
        }

        /// Makes the mutation field of one call, with random arguments.
        ///
        /// - Parameters:
        ///   - tasks: The tasks of the board, live or tombstoned. The list must not be empty.
        ///   - generator: The source of random numbers.
        /// - Returns: The field.
        func field(choosingFrom tasks: [ULID], using generator: inout SplitMix64) -> String {
            typealias Tests = Design.ReplayPropertyTests
            let task = Tests.pick(from: tasks, using: &generator)
            switch self {
            case .addTask:
                let inputs = [
                    "",
                    TaskOperationTests.tagsInput(Tests.pick(from: Tests.tags, using: &generator)),
                    AddUpdateTaskTests.dependsOn(task),
                ]
                return AddUpdateTaskTests.addTask(with: Tests.pick(from: inputs, using: &generator))
            case .updateTitle:
                return UndoTests.titleField(Tests.pick(from: Tests.titles, using: &generator), of: task)
            case .updateBody:
                return UndoTests.bodyField(Tests.pick(from: Tests.bodies, using: &generator), of: task)
            case .updateDependencies:
                let dependency = Tests.pick(from: tasks, using: &generator)
                return AddUpdateTaskTests.updateTask(task, with: AddUpdateTaskTests.dependsOn(dependency))
            case .moveTask:
                let move = TaskOperationTests.moveInput(to: Tests.pick(from: Tests.columns, using: &generator))
                return TaskOperationTests.taskField(mutationName, of: task, with: move)
            case .completeTask, .deleteTask, .undeleteTask:
                return TaskOperationTests.taskField(mutationName, of: task)
            case .assignTask, .unassignTask:
                let actor = TaskOperationTests.actorInput(naming: Tests.pick(from: Tests.actors, using: &generator))
                return TaskOperationTests.taskField(mutationName, of: task, with: actor)
            case .tagTask, .untagTask:
                let tag = TaskOperationTests.tagsInput(Tests.pick(from: Tests.tags, using: &generator))
                return TaskOperationTests.taskField(mutationName, of: task, with: tag)
            case .addComment:
                return CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: task))
            case .renameTag:
                let source = Tests.pick(from: Tests.tags, using: &generator)
                let target = Tests.pick(from: Tests.tags.filter { tag in tag != source }, using: &generator)
                return TagMutationTests.renameTag(from: source, to: target)
            case .undo, .redo:
                return UndoTests.reverseField(mutationName, with: "")
            }
        }
    }
}
