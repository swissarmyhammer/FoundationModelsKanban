import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that makes a tag. It is idempotent on the slug.
    static let addTag = "addTag"

    /// The mutation that changes the name, the color, or the body of a tag. The slug does not change.
    static let updateTag = "updateTag"

    /// The mutation that makes a tag a tombstone.
    static let deleteTag = "deleteTag"

    /// The mutation that makes a tombstoned tag live again.
    static let undeleteTag = "undeleteTag"

    /// The mutation that renames a tag with a redirect (plan.md §6.2).
    static let renameTag = "renameTag"
}

// MARK: - Arguments

/// The `input` object of `addTag` (plan.md §4.2). The input gives the id, the name, or the two.
private struct AddTagInput: Decodable, Sendable {
    /// The id of the tag, or `nil` for the slug of ``name``. The id is the slug of this text (plan.md §3.2).
    let id: NodeID?

    /// The tag name, or `nil` for the text of ``id``. The tag name rule applies (plan.md §6).
    let name: String?

    /// The color of the tag, or `nil` for the auto color of the slug.
    let color: String?

    /// The Markdown body of the tag: the full text, or `nil` for no body.
    let body: String?

    /// The board of the tag: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6).
    let board: String?
}

/// The `input` object of `updateTag` (plan.md §4.2). A field that is not set does not change, and `null` clears the
/// field.
private struct UpdateTagInput: Decodable, Sendable {
    /// The tag: a full URI, the slug, or a tag name (plan.md §3.2). A renamed slug names the rename target.
    let id: NodeID

    /// The new name of the tag. The tag name rule applies, and the slug does not change.
    let name: FieldUpdate<String>

    /// The new color of the tag.
    let color: FieldUpdate<String>

    /// The new Markdown body of the tag: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of `renameTag` (plan.md §4.2, §6.2).
private struct RenameTagInput: Decodable, Sendable {
    /// The tag to rename: a full URI, the slug, or a tag name. A renamed slug names the rename target.
    let from: NodeID

    /// The new tag name. Its slug is the slug of the redirect target, also when a rename redirects that slug.
    let to: String

    /// The board of the tag when `from` is not a full URI: a board key, a repo directory name, or a path, or `nil`
    /// for the current board (plan.md §6.6). A full URI names the tag in its own board.
    let board: String?
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addTag`: makes a tag with a `set` of the name and the color, and an `edit` of the body, in
    /// one patch (plan.md §4.2). The color is the auto color of the slug when the input gives no color.
    ///
    /// The mutation is idempotent on the slug: when the board has the tag, the mutation follows the rename redirect,
    /// and returns the tag at the end of the chain with no change. A tombstone at the end of the chain gets a
    /// `delete: false` patch.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new tag. The `input` argument is optional, because ``AddTagInput`` has no required field
    ///     (plan.md §4.2). No `input` is the same as an `input` with no field.
    /// - Returns: The tag. The GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/invalidTagName(name:)`` when the id or the name gives an empty slug, or when the input
    ///   gives no id and no name. ``KanbanError/reservedTagName`` when a new tag would get the slug
    ///   ``Slug/reservedForBoard``. ``KanbanError/virtualTagName(tag:)`` when a new tag would get the name of a
    ///   virtual tag as its slug.
    fileprivate func addTag(
        context: KanbanContext,
        arguments: OptionalInputArguments<AddTagInput>
    ) async throws -> TagObject? {
        let input = arguments.input
        return try await context.changeNode(named: MutationName.addTag, on: .named(input?.board)) { work, _, time in
            let name = try TagName(normalizing: input?.name ?? input?.id?.text ?? "")
            let slug = try input?.id.map { id in try TagName(normalizing: id.text).slug } ?? name.slug
            let values = [
                PropertyName.name: PatchValue.string(name.name),
                PropertyName.color: .string(input?.color ?? slug.autoColor),
            ]
            return try work.ensureLiveTag(.tag(slug: slug.value), setting: values, body: input?.body, at: time)
        }
    }

    /// Resolves `Mutation.updateTag`: changes the given fields of a tag. The slug does not change. A renamed slug
    /// names the rename target (plan.md §6.2).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tag and the changes.
    /// - Returns: The tag after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live tag has the id.
    ///   ``KanbanError/invalidTagName(name:)`` when the new name gives an empty slug.
    fileprivate func updateTag(
        context: KanbanContext,
        arguments: InputArguments<UpdateTagInput>
    ) async throws -> TagObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        return try await context.changeNode(named: MutationName.updateTag, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .tag)
            let name = try input.name.map { name in try TagName(normalizing: name).name }
            let values = [
                PropertyName.name: name.map(PatchValue.string),
                PropertyName.color: input.color.map(PatchValue.string),
            ]
            try work.updateNode(ref, updating: values, body: input.body, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.deleteTag`: makes the tag a tombstone (plan.md §3.3). A renamed slug names the rename
    /// target, so the target gets the tombstone (plan.md §6.2).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tag.
    /// - Returns: The tombstone, with `deleted` set.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live tag has the id.
    fileprivate func deleteTag(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> TagObject? {
        try await changeDeleted(to: true, ofType: .tag, as: MutationName.deleteTag, context: context, arguments)
    }

    /// Resolves `Mutation.undeleteTag`: makes a tombstoned tag live again. A live tag does not change.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tag.
    /// - Returns: The live tag.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no tag has the id.
    fileprivate func undeleteTag(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> TagObject? {
        try await changeDeleted(to: false, ofType: .tag, as: MutationName.undeleteTag, context: context, arguments)
    }

    /// Resolves `Mutation.renameTag`: renames a tag with a redirect (plan.md §6.2). No task changes.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tag and the new name.
    /// - Returns: The live tag at the end of the rename chain of the renamed tag.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live tag has the `from` ref.
    ///   ``KanbanError/invalidTagName(name:)`` when the new name gives an empty slug.
    ///   ``KanbanError/reservedTagName`` when the new tag would get the slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/virtualTagName(tag:)`` when the new tag would get the name of a virtual tag as its slug.
    ///   ``KanbanError/tagRenameCycle(path:)`` when the redirect makes a rename cycle.
    fileprivate func renameTag(
        context: KanbanContext,
        arguments: InputArguments<RenameTagInput>
    ) async throws -> TagObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.from, orNamed: input.board)
        return try await context.changeNode(named: MutationName.renameTag, on: board) { work, resolver, time in
            let source = try resolver.nodeRef(for: input.from, ofType: .tag)
            return try work.renameTag(source, to: TagName(normalizing: input.to), at: time)
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Makes a tag live, and gives the tag that a ref to it names (plan.md §6.1, §6.2).
    ///
    /// - An unknown tag gets one patch: a `set` of the values and an `edit` of the body.
    /// - A tag that the graph has gets no `set` and no `edit`. The ref follows the rename redirect, and a tombstone at
    ///   the end of the chain gets a `delete: false` patch. A live tag gets no patch.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the tag.
    ///   - values: The properties of an unknown tag.
    ///   - body: The body of an unknown tag, or `nil` for no body.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the tag at the end of the rename chain.
    /// - Throws: ``KanbanError/reservedTagName`` when an unknown tag has the slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/virtualTagName(tag:)`` when an unknown tag has the name of a virtual tag as its slug. An
    ///   ``EventError`` when a patch breaks a rule of the log.
    mutating func ensureLiveTag(
        _ ref: LocalRef,
        setting values: [String: PatchValue],
        body: String? = nil,
        at time: DateTime
    ) throws -> LocalRef {
        guard graph.hasNode(ref) else {
            try addNode(ref, setting: values, body: body, at: time)
            return ref
        }
        let target = graph.tagRef(redirectedFrom: ref)
        try apply(PatchInput(node: target, delete: false), at: time)
        return target
    }

    /// Renames a tag with a redirect (plan.md §6.2). The rename writes up to two patches:
    ///
    /// 1. When the graph does not have the new slug: the new tag gets a `set` of the new name and of the color of the
    ///    old tag, and an `edit` with the body of the old tag.
    /// 2. The old tag gets a `set` of `renamedTo`.
    ///
    /// A rename to a slug that the graph has is a merge: patch 1 is not written. When the end of the rename chain of
    /// that slug is a tombstone, that tag gets a `delete: false` patch before patch 2, the same as in
    /// ``ensureLiveTag(_:setting:body:at:)``. A rename to the slug of the tag itself writes nothing.
    ///
    /// - Parameters:
    ///   - source: The local ref of the tag to rename.
    ///   - name: The new tag name.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the tag at the end of the rename chain of the renamed tag.
    /// - Throws: ``KanbanError/tagRenameCycle(path:)`` when the redirect makes a rename cycle. An ``EventError`` when
    ///   a patch breaks a rule of the log.
    fileprivate mutating func renameTag(_ source: LocalRef, to name: TagName, at time: DateTime) throws -> LocalRef {
        let target = LocalRef.tag(slug: name.slug.value)
        guard target != source else {
            return source
        }
        let color = (graph.node(for: source)?.state as? TagNode)?.resolvedColor
        let values = [String: PatchValue](
            givenValues: [PropertyName.name: .string(name.name), PropertyName.color: color.map(PatchValue.string)]
        )
        _ = try ensureLiveTag(target, setting: values, body: graph.body(of: source), at: time)
        try apply(PatchInput(node: source, set: [PropertyName.renamedTo: .ref(.local(target))]), at: time)
        let start = graph.slot(for: source)
        try checkNoRenameCycle(fromTagAt: start)
        return start.flatMap(graph.renameTarget(ofTagAt:)).flatMap(graph.node(at:))?.ref ?? target
    }

    /// Checks that the rename chain from a tag has no cycle (plan.md §6.2).
    ///
    /// - Parameter start: The slot of the first tag, or `nil` when the graph does not have the tag.
    /// - Throws: ``KanbanError/tagRenameCycle(path:)`` with the slug of each tag on the walk, from the first tag to
    ///   the first slug that repeats.
    func checkNoRenameCycle(fromTagAt start: Int?) throws(KanbanError) {
        guard let cycle = start.flatMap(graph.renameCycle(fromTagAt:)) else {
            return
        }
        throw .tagRenameCycle(path: cycle.compactMap { slot in graph.node(at: slot, as: TagNode.self)?.slug })
    }
}

extension Graph {
    /// Walks the `renamedTo` edges from a tag, and finds a cycle.
    ///
    /// - Parameter start: The slot of the first tag.
    /// - Returns: The slots of the walk, from the first tag to the first slot that repeats, with that slot at the two
    ///   ends of the cycle part. `nil` when the walk ends at a tag with no resolved `renamedTo` edge.
    fileprivate func renameCycle(fromTagAt start: Int) -> [Int]? {
        var walk: [Int] = []
        var current: Int? = start
        while let slot = current, !walk.contains(slot) {
            walk.append(slot)
            current = node(at: slot, as: TagNode.self)?.renamedTo?.resolvedSlot
        }
        return current.map { repeated in walk + [repeated] }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the tag mutations and their `input` types (plan.md §4.2). The delete and the undelete mutations use the
    /// `input` type of ``NodeReferenceInput``, which ``addColumnActorMutations()`` adds.
    ///
    /// - Returns: This builder, for method chaining.
    func addTagMutations() -> Self {
        add {
            Input(AddTagInput.self) {
                InputField("id", at: \.id)
                InputField("name", at: \.name)
                InputField("color", at: \.color)
                InputField("body", at: \.body)
                InputField("board", at: \.board)
            }
            Input(UpdateTagInput.self) {
                InputField("id", at: \.id)
                InputField("name", at: \.name.value)
                InputField("color", at: \.color.value)
                InputField("body", at: \.body.value)
            }
            Input(RenameTagInput.self) {
                InputField("from", at: \.from)
                InputField("to", at: \.to)
                InputField("board", at: \.board)
            }
        }
        .addMutation {
            Field(MutationName.addTag, at: KanbanResolver.addTag) { Argument("input", at: \.input) }
            Field(MutationName.updateTag, at: KanbanResolver.updateTag) { Argument("input", at: \.input) }
            Field(MutationName.deleteTag, at: KanbanResolver.deleteTag) { Argument("input", at: \.input) }
            Field(MutationName.undeleteTag, at: KanbanResolver.undeleteTag) { Argument("input", at: \.input) }
            Field(MutationName.renameTag, at: KanbanResolver.renameTag) { Argument("input", at: \.input) }
        }
    }
}
