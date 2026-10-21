import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that adds a comment to a task.
    static let addComment = "addComment"

    /// The mutation that changes the body of a comment.
    static let updateComment = "updateComment"

    /// The mutation that makes a comment a tombstone.
    static let deleteComment = "deleteComment"

    /// The mutation that makes a tombstoned comment live again.
    static let undeleteComment = "undeleteComment"
}

// MARK: - Arguments

/// The `input` object of `addComment` (plan.md §4.2).
private struct AddCommentInput: Decodable, Sendable {
    /// The task of the comment: a full URI or a short form (plan.md §3.2).
    let task: NodeID

    /// The Markdown body of the comment: the full text.
    let body: String

    /// The author of the comment: a full URI or the slug of an actor, or `nil` for the session actor. A slug or a
    /// name that names no actor makes the actor.
    let actor: NodeID?
}

/// The `input` object of `updateComment` (plan.md §4.2). A body that is not set does not change, and `null` clears
/// the body.
private struct UpdateCommentInput: Decodable, Sendable {
    /// The comment: a full URI or a short form (plan.md §3.2). The task of the comment is not necessary.
    let id: NodeID

    /// The task of the comment, or `nil` for no check (divergence.md E5, K16). The Rust form of the call gives the
    /// task of the comment beside its id.
    let task: NodeID?

    /// The new Markdown body of the comment: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of `deleteComment` and `undeleteComment` (plan.md §4.2): the comment, and the task of the
/// comment as a check (divergence.md E5, K16).
private struct CommentReferenceInput: Decodable, Sendable {
    /// The comment: a full URI or a short form (plan.md §3.2). The task of the comment is not necessary.
    let id: NodeID

    /// The task of the comment, or `nil` for no check.
    let task: NodeID?
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addComment`: mints the comment ULID, and writes one comment patch with a `set` of the task
    /// and the author, and an `edit` diff of the body (plan.md §3.2, §4.2). An author that the board does not have
    /// gets an actor `set` patch first.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new comment.
    /// - Returns: The comment. The GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the ref.
    ///   ``KanbanError/actorNotFound(reference:)`` when an actor URI names no actor.
    ///   ``KanbanError/invalidSlug(name:)`` when an actor name gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when a new actor would get the slug ``Slug/reservedForBoard``.
    fileprivate func addComment(
        context: KanbanContext,
        arguments: InputArguments<AddCommentInput>
    ) async throws -> CommentObject? {
        let input = arguments.input
        let sessionActor = context.store.sessionActor.ref
        let board = MutationBoard.holding(input.task)
        return try await context.changeNode(named: MutationName.addComment, on: board) { work, resolver, time in
            let task = try resolver.nodeRef(for: input.task, ofType: .task)
            let author = try work.authorRef(
                for: input.actor,
                defaultingTo: sessionActor,
                resolvingWith: resolver,
                at: time
            )
            let ref = LocalRef.comment(work.mintULID())
            let values = [PropertyName.task: PatchValue.ref(.local(task)), PropertyName.author: .ref(.local(author))]
            try work.addNode(ref, setting: values, body: input.body, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.updateComment`: writes the `edit` diff from the current body. The comment id alone names
    /// the comment (plan.md §3.2). A task in the input must be the task of the comment (divergence.md K16).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The comment and the new body.
    /// - Returns: The comment after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live comment has the id, or the input names a task
    ///   that is not the task of the comment.
    fileprivate func updateComment(
        context: KanbanContext,
        arguments: InputArguments<UpdateCommentInput>
    ) async throws -> CommentObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        return try await context.changeNode(named: MutationName.updateComment, on: board) { work, resolver, time in
            let ref = try resolver.commentRef(for: input.id, onTask: input.task)
            try work.updateNode(ref, updating: [:], body: input.body, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.deleteComment`: makes the comment a tombstone (plan.md §3.3). The comment id alone names the
    /// comment. A task in the input must be the task of the comment (divergence.md K16).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The comment.
    /// - Returns: The tombstone, with `deleted` set.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live comment has the id, or the input names a task
    ///   that is not the task of the comment.
    fileprivate func deleteComment(
        context: KanbanContext,
        arguments: InputArguments<CommentReferenceInput>
    ) async throws -> CommentObject? {
        try await changeDeleted(ofComment: arguments.input, to: true, as: MutationName.deleteComment, context: context)
    }

    /// Resolves `Mutation.undeleteComment`: makes a tombstoned comment live again. A live comment does not change. A
    /// task in the input must be the task of the comment (divergence.md K16).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The comment.
    /// - Returns: The live comment.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no comment has the id, or the input names a task that
    ///   is not the task of the comment.
    fileprivate func undeleteComment(
        context: KanbanContext,
        arguments: InputArguments<CommentReferenceInput>
    ) async throws -> CommentObject? {
        let operation = MutationName.undeleteComment
        return try await changeDeleted(ofComment: arguments.input, to: false, as: operation, context: context)
    }

    /// Writes a `delete` patch on a comment with ``changeDeleted(to:as:context:holding:resolving:)``, after the check
    /// of the task in the input.
    ///
    /// - Parameters:
    ///   - input: The comment, and the task of the comment or `nil`.
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - operation: The name of the public mutation.
    ///   - context: The context of the call.
    /// - Returns: The comment after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no comment that the change accepts has the id, or the
    ///   input names a task that is not the task of the comment.
    private func changeDeleted(
        ofComment input: CommentReferenceInput,
        to isDeleted: Bool,
        as operation: String,
        context: KanbanContext
    ) async throws -> CommentObject? {
        try await changeDeleted(to: isDeleted, as: operation, context: context, holding: input.id) { resolver in
            try resolver.commentRef(for: input.id, onTask: input.task, includingTombstones: !isDeleted)
        }
    }
}

// MARK: - Refs

extension RefResolver {
    /// Changes the forgiving ref of a comment to its local ref, and checks that the comment is on the task that the
    /// input names (divergence.md E5, K16).
    ///
    /// - Parameters:
    ///   - id: The comment ref as the caller wrote it.
    ///   - task: The task ref that the input gives beside the comment, or `nil` for no check. It can name a
    ///     tombstoned task.
    ///   - includesTombstones: `true` when the comment ref can name a tombstone.
    /// - Returns: The local ref of the comment.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no comment that the lookup accepts has the ref, when no
    ///   task has the task ref, or when the comment is not on that task. The comment error names the comment ref.
    fileprivate func commentRef(
        for id: NodeID,
        onTask task: NodeID?,
        includingTombstones includesTombstones: Bool = false
    ) throws(KanbanError) -> LocalRef {
        let ref = try nodeRef(for: id, ofType: .comment, includingTombstones: includesTombstones)
        guard let task else {
            return ref
        }
        let taskRef = try nodeRef(for: task, ofType: .task, includingTombstones: true)
        let comment = graph.node(for: ref)?.state as? CommentNode
        guard let edge = comment?.task, graph.storedRef(of: edge) == .local(taskRef) else {
            throw .notFound(type: .comment, reference: id.text)
        }
        return ref
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Finds the author of a new comment (plan.md §4.2). An actor that the board has, live or tombstoned, gets no
    /// patch: the projection shows a tombstoned author with `deleted` set (``Graph/author(ofCommentAt:)``). An actor
    /// slug or name that names no actor gets an actor `set name` patch with the text as the name.
    ///
    /// - Parameters:
    ///   - id: The actor as the caller wrote it: a full URI, a slug, or a name. `nil` gives the session actor.
    ///   - sessionActor: The local ref of the session actor of the call.
    ///   - resolver: The resolver of the forgiving refs of the board, for an actor URI.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the author.
    /// - Throws: ``KanbanError/actorNotFound(reference:)`` when an actor URI names no actor.
    ///   ``KanbanError/invalidSlug(name:)`` when a name gives an empty slug. ``KanbanError/reservedSlug(type:)`` when
    ///   the name of a new actor gives the slug ``Slug/reservedForBoard``. An ``EventError`` when the actor patch
    ///   breaks a rule of the log.
    fileprivate mutating func authorRef(
        for id: NodeID?,
        defaultingTo sessionActor: LocalRef,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> LocalRef {
        guard let id else {
            return sessionActor
        }
        guard !NodeURI.hasScheme(atStartOf: id.text) else {
            return try resolver.actorRef(for: id, includingTombstones: true)
        }
        let ref = LocalRef.actor(slug: try Slug(columnOrActorName: id.text).value)
        guard !graph.hasNode(ref) else {
            return ref
        }
        try ref.checkSlugIsNotReserved()
        try apply(PatchInput(node: ref, set: [PropertyName.name: .string(id.text)]), at: time)
        return ref
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the comment mutations and their `input` types (plan.md §4.2). The delete and the undelete mutations use
    /// the `input` type of ``CommentReferenceInput``, so that the Rust form of the call, with the task of the
    /// comment, runs (divergence.md E5).
    ///
    /// - Returns: This builder, for method chaining.
    func addCommentMutations() -> Self {
        add {
            Input(AddCommentInput.self) {
                InputField("task", at: \.task)
                InputField("body", at: \.body)
                InputField("actor", at: \.actor)
            }
            Input(UpdateCommentInput.self) {
                InputField("id", at: \.id)
                InputField("body", at: \.body.value)
                InputField("task", at: \.task).description(SchemaDescription.commentTask)
            }
            Input(CommentReferenceInput.self) {
                InputField("id", at: \.id)
                InputField("task", at: \.task).description(SchemaDescription.commentTask)
            }
        }
        .addMutation {
            Field(MutationName.addComment, at: KanbanResolver.addComment) { Argument("input", at: \.input) }
            Field(MutationName.updateComment, at: KanbanResolver.updateComment) { Argument("input", at: \.input) }
            Field(MutationName.deleteComment, at: KanbanResolver.deleteComment) { Argument("input", at: \.input) }
            Field(MutationName.undeleteComment, at: KanbanResolver.undeleteComment) {
                Argument("input", at: \.input)
            }
        }
    }
}
