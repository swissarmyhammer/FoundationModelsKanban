import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `renameTag` to the slug of a tombstoned tag (plan.md §6.2, §6.5). A rename to a slug that exists is a merge,
/// so the rename writes `delete: false` on the tombstone, and the tasks with the old tag show the target. `undo` of the
/// rename reverses the two patches.
///
/// Each test runs ``ChangeBuilderTests/baseSetup``, which adds ``TagMutationTests/bug``, in a commit session of the
/// fixture board. Then the test runs three calls: a `tagTask` of the fixture task with `bug`, an `addTag` of
/// ``TagMutationTests/defect``, and a `deleteTag` of `defect`.
@Suite("Tag rename to a deleted tag")
struct TagRenameToTombstoneTests {
    /// The local ref of the rename target ``TagMutationTests/defect``.
    static let defectTag = LocalRef.tag(slug: TagMutationTests.defect)

    /// The selection of the `renameTag` field: the id of the tag and the time of its delete.
    static let renameSelection = "{ id deleted }"

    /// The `delete` values of the patches on the target after the rename: the `deleteTag` of the setup, then the
    /// `delete: false` of the rename.
    static let deletesAfterRename = [true, false]

    /// The `delete` values of the patches on the target after the undo of the rename: ``deletesAfterRename``, then the
    /// `delete: true` of the undo.
    static let deletesAfterUndo = deletesAfterRename + [true]

    // MARK: - Helpers

    /// Runs the base setup, then the three setup calls of this suite, each in its own transaction.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The session after the setup, and the ULID of the fixture task.
    static func sessionWithDeletedTarget(
        inRepoAt directory: TemporaryDirectory
    ) async throws -> (session: CommitSession, task: ULID) {
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let fields = [
            ChangeBuilderTests.tagField(of: ChangeBuilderTests.refs(of: base.task, in: session)),
            TagMutationTests.addTag(named: TagMutationTests.defect),
            CommentTests.nodeField(MutationName.deleteTag, naming: TagMutationTests.defect),
        ]
        try await HistoryTests.run(eachOf: fields, in: &session)
        return (session, base.task)
    }

    /// Runs `renameTag` from ``TagMutationTests/bug`` to ``TagMutationTests/defect`` in its own call.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The value of the `renameTag` field, with ``renameSelection``.
    @discardableResult
    static func renameBugToDefect(in session: inout CommitSession) async throws -> Map {
        let field = TagMutationTests.renameTag(
            from: TagMutationTests.bug,
            to: TagMutationTests.defect,
            selecting: renameSelection
        )
        let result = try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: field), in: &session)
        return result.data?[MutationName.renameTag] ?? .null
    }

    /// Gives the patches of the log of the target: the patch of the `addTag` of the setup, then one `delete` patch for
    /// each value.
    ///
    /// - Parameter deletes: The `delete` values of the patches after the `addTag`, in log order.
    /// - Returns: The patches.
    static func targetPatches(deleting deletes: [Bool]) throws -> [PatchInput] {
        let setting = TagMutationTests.autoColorSetting(of: TagMutationTests.defect)
        let added = try PatchInput(node: defectTag, set: setting)
        return try [added] + deletes.map { isDeleted in try PatchInput(node: defectTag, delete: isDeleted) }
    }

    // MARK: - Rename

    @Test("renameTag to a deleted tag writes delete false on the target, and returns the live target")
    func renameRevivesTarget() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.sessionWithDeletedTarget(inRepoAt: directory).session
        let renamed = try await Self.renameBugToDefect(in: &session)
        #expect(renamed == ["id": Map(ColumnActorTests.id(of: Self.defectTag)), "deleted": .null])
        let patches = try ColumnActorTests.patches(of: Self.defectTag, in: directory)
        #expect(try patches == Self.targetPatches(deleting: Self.deletesAfterRename))
    }

    @Test("After renameTag to a deleted tag, the task with the old tag shows the target")
    func renamedTaskShowsTarget() async throws {
        let directory = try TemporaryDirectory()
        let setup = try await Self.sessionWithDeletedTarget(inRepoAt: directory)
        var session = setup.session
        try await Self.renameBugToDefect(in: &session)
        let task = UndoTests.projection(of: session)[.task(setup.task)]
        #expect(task?["tags"] == .list([Map(ColumnActorTests.id(of: Self.defectTag))]))
    }

    // MARK: - Undo

    @Test("undo of renameTag to a deleted tag gives the projection before the rename, and deletes the target again")
    func undoRestoresDeletedTarget() async throws {
        let directory = try TemporaryDirectory()
        var session = try await Self.sessionWithDeletedTarget(inRepoAt: directory).session
        let before = UndoTests.projection(of: session)
        try await Self.renameBugToDefect(in: &session)
        try await UndoTests.reverse(in: &session)
        #expect(UndoTests.projection(of: session) == before)
        let patches = try ColumnActorTests.patches(of: Self.defectTag, in: directory)
        #expect(try patches == Self.targetPatches(deleting: Self.deletesAfterUndo))
    }
}
