import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that makes a tag. It is idempotent on the slug.
    static let addTag = "addTag"

    /// The mutation that changes the name, the color, or the body of a tag. A name of a new slug renames the tag, the
    /// same as ``renameTag`` (divergence.md C4).
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
    /// The id of the tag, or `nil` for the slug of ``name``. The id is the slug of this text, or the slug of a full
    /// tag URI of the board (plan.md §3.2).
    let id: NodeID?

    /// The tag name, or `nil` for the text of ``id``, or the slug of a URI ``id``. The tag name rule applies
    /// (plan.md §6).
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
/// field. The `name` is required, so `null` does not change it (``IgnoredNull``).
private struct UpdateTagInput: Decodable, Sendable {
    /// The tag: a full URI, the slug, or a tag name (plan.md §3.2). A renamed slug names the rename target.
    let id: NodeID

    /// The new name of the tag. The tag name rule applies. A name of the same slug changes only the display name, and
    /// a name of a new slug renames the tag (divergence.md C4). `null` gives no change and a warning (``IgnoredNull``).
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
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the id is a URI that does not name a tag of the
    ///   board. ``KanbanError/invalidTagName(name:)`` when the id or the name gives an empty slug, or when the input
    ///   gives no id and no name. ``KanbanError/reservedTagName`` when a new tag would get the slug
    ///   ``Slug/reservedForBoard``. ``KanbanError/virtualTagName(tag:)`` when a new tag would get the name of a
    ///   virtual tag as its slug.
    fileprivate func addTag(
        context: KanbanContext,
        arguments: OptionalInputArguments<AddTagInput>
    ) async throws -> TagObject? {
        let input = arguments.input
        let board = MutationBoard.named(input?.board)
        return try await context.changeNode(named: MutationName.addTag, on: board) { work, resolver, time in
            let key = try resolver.newNodeKey(for: input?.id, named: input?.name ?? "", ofType: .tag)
            let name = try TagName(normalizing: input?.name ?? key)
            let slug = try TagName(normalizing: key).slug
            let values = [
                PropertyName.name: PatchValue.string(name.name),
                PropertyName.color: .string(input?.color ?? slug.autoColor),
            ]
            return try work.ensureLiveTag(.tag(slug: slug.value), setting: values, body: input?.body, at: time)
        }
    }

    /// Resolves `Mutation.updateTag`: changes the given fields of a tag. A renamed slug names the rename target
    /// (plan.md §6.2).
    ///
    /// A name whose slug is the slug of the tag changes only the display name. A name whose slug is different renames
    /// the tag, the same as `renameTag` (divergence.md C4, E1): a redirect from the old slug, or a merge into a tag
    /// that has the new slug, and the same errors. The color and the body then go to the tag at the end of the rename.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tag and the changes.
    /// - Returns: The tag after the change: the tag at the end of the rename chain when the name renames the tag.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live tag has the id.
    ///   ``KanbanError/invalidTagName(name:)`` when the new name gives an empty slug.
    ///   ``KanbanError/reservedTagName`` when the new name renames the tag to the slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/virtualTagName(tag:)`` when the new name renames the tag to the name of a virtual tag.
    ///   ``KanbanError/tagRenameCycle(path:)`` when the rename makes a rename cycle.
    fileprivate func updateTag(
        context: KanbanContext,
        arguments: InputArguments<UpdateTagInput>
    ) async throws -> TagObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        let tag: TagObject? = try await context.changeNode(
            named: MutationName.updateTag,
            on: board
        ) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .tag)
            let name = try input.name.ignoringNull.map(TagName.init(normalizing:))
            return try work.updateTag(ref, naming: name, color: input.color, body: input.body, at: time)
        }
        await context.warnIfNull(input.name, forField: PropertyName.name, of: MutationName.updateTag)
        return tag
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
        return try undeleteTag(redirectedFrom: ref, at: time)
    }

    /// Follows the rename redirect from a tag that the graph has, and makes the tag at the end of the chain live
    /// (plan.md §6.2).
    ///
    /// Only a tombstone at the end of the chain gets a `delete: false` patch. A live tag at the end of the chain gets
    /// no patch. This check is explicit, so the contract does not depend on the commit path, which also drops a patch
    /// that changes nothing.
    ///
    /// - Parameters:
    ///   - ref: The local ref of a tag that the graph has.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the tag at the end of the rename chain.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    private mutating func undeleteTag(redirectedFrom ref: LocalRef, at time: DateTime) throws(EventError) -> LocalRef {
        let target = graph.tagRef(redirectedFrom: ref)
        if graph.node(for: target)?.state.fields.isDeleted == true {
            try apply(PatchInput(node: target, delete: false), at: time)
        }
        return target
    }

    /// Renames a tag with a redirect (plan.md §6.2). The rename writes up to two patches:
    ///
    /// 1. When the graph does not have the new slug: the new tag gets a `set` of the new name and of the color of the
    ///    old tag, and an `edit` with the body of the old tag.
    /// 2. The old tag gets a `set` of `renamedTo`.
    ///
    /// A rename to a slug that the graph has is a merge: patch 1 is not written. The merge writes a patch on the target
    /// only when the end of the rename chain of that slug is a tombstone: that tag gets a `delete: false` patch before
    /// patch 2, from ``undeleteTag(redirectedFrom:at:)``. A merge into a live tag writes no patch on the target. A
    /// rename to the slug of the tag itself writes nothing.
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
        if graph.hasNode(target) {
            _ = try undeleteTag(redirectedFrom: target, at: time)
        } else {
            let color = (graph.node(for: source)?.state as? TagNode)?.resolvedColor
            let values = [String: PatchValue](
                givenValues: [PropertyName.name: .string(name.name), PropertyName.color: color.map(PatchValue.string)]
            )
            try addNode(target, setting: values, body: graph.body(of: source), at: time)
        }
        try apply(PatchInput(node: source, set: [PropertyName.renamedTo: .ref(.local(target))]), at: time)
        let start = graph.slot(for: source)
        try checkNoRenameCycle(fromTagAt: start)
        return start.flatMap(graph.renameTarget(ofTagAt:)).flatMap(graph.node(at:))?.ref ?? target
    }

    /// Changes the given fields of a tag (divergence.md C4, E1).
    ///
    /// A name whose slug is different from the slug of the tag renames the tag with ``renameTag(_:to:at:)``, and the
    /// color and the body go to the tag at the end of the rename. That tag keeps its own name: the new tag of a rename
    /// gets the new name, and the target of a merge keeps its name. A name of the same slug is the new display name.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the tag.
    ///   - name: The new name of the tag.
    ///   - color: The new color of the tag.
    ///   - body: The new body of the tag: the full text.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the changed tag: the tag at the end of the rename chain when the name renames the
    ///   tag.
    /// - Throws: The errors of ``renameTag(_:to:at:)`` and of the new tag of the rename. An ``EventError`` when a patch
    ///   breaks a rule of the log.
    fileprivate mutating func updateTag(
        _ ref: LocalRef,
        naming name: FieldUpdate<TagName>,
        color: FieldUpdate<String>,
        body: FieldUpdate<String>,
        at time: DateTime
    ) throws -> LocalRef {
        let newSlugName = Self.name(name, renaming: ref)
        let target = try newSlugName.map { newName in try renameTag(ref, to: newName, at: time) } ?? ref
        let displayName = newSlugName == nil ? name.map { newName in PatchValue.string(newName.name) } : .unchanged
        let values = [PropertyName.name: displayName, PropertyName.color: color.map(PatchValue.string)]
        try updateNode(target, updating: values, body: body, at: time)
        return target
    }

    /// Gives the new name of a tag when the name renames the tag: when its slug is different from the slug of the tag
    /// (divergence.md C4).
    ///
    /// - Parameters:
    ///   - name: The new name of the tag.
    ///   - ref: The local ref of the tag.
    /// - Returns: The new name, or `nil` when the input gives no name or a name of the same slug.
    private static func name(_ name: FieldUpdate<TagName>, renaming ref: LocalRef) -> TagName? {
        guard case .changed(let newName) = name, LocalRef.tag(slug: newName.slug.value) != ref else {
            return nil
        }
        return newName
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
                InputField("id", at: \.id).description(SchemaDescription.newTagID)
                InputField("name", at: \.name).description(SchemaDescription.newTagName)
                InputField("color", at: \.color).description(SchemaDescription.newTagColor)
                InputField("body", at: \.body).description(SchemaDescription.newNodeBody)
                InputField("board", at: \.board).description(SchemaDescription.boardToChange)
            }
            .description(SchemaDescription.addTagInput)
            Input(UpdateTagInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.tagReference)
                InputField("name", at: \.name.value).description(SchemaDescription.changedTagName)
                InputField("color", at: \.color.value).description(SchemaDescription.changedColor)
                InputField("body", at: \.body.value).description(SchemaDescription.changedBody)
            }
            .description(SchemaDescription.updateTagInput)
            Input(RenameTagInput.self) {
                InputField("from", at: \.from).description(SchemaDescription.renameFrom)
                InputField("to", at: \.to).description(SchemaDescription.renameTo)
                InputField("board", at: \.board).description(SchemaDescription.boardToChange)
            }
            .description(SchemaDescription.renameTagInput)
        }
        .addMutation {
            Self.mutationField(MutationName.addTag, at: KanbanResolver.addTag, description: SchemaDescription.addTag)
            Self.mutationField(
                MutationName.updateTag,
                at: KanbanResolver.updateTag,
                description: SchemaDescription.updateTag
            )
            Self.mutationField(
                MutationName.deleteTag,
                at: KanbanResolver.deleteTag,
                description: SchemaDescription.deleteTag
            )
            Self.mutationField(
                MutationName.undeleteTag,
                at: KanbanResolver.undeleteTag,
                description: SchemaDescription.undeleteTag
            )
            Self.mutationField(
                MutationName.renameTag,
                at: KanbanResolver.renameTag,
                description: SchemaDescription.renameTag
            )
        }
    }
}
