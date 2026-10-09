import Foundation

/// Changes a forgiving ref that a caller writes to the stored ref of a node of one board (plan.md §3.2, §4.4).
///
/// The resolver reads the ``Graph`` of the target board. It accepts these forms, and the expected node type decides
/// how it reads a form that is not a URI:
///
/// - A full `kanban://` URI. A URI with the key of the board gives a local ref. A URI with a different key gives a
///   remote ref, but only when the caller accepts a ref to a node of a different board.
/// - For a task or a comment: a full ULID, a short id, `^short`, or a unique ULID prefix. The compare ignores case,
///   and a canonical form wins over a prefix of the same characters (``ShortID/resolve(_:among:)``).
/// - For a column or an actor: the slug, or a name that gives the slug (``Slug/normalizedText(of:)``).
/// - For a tag: the slug, or a tag name that gives the slug (``TagName``). The resolve then follows the rename
///   redirect (plan.md §6.2), so a ref to an old slug gives the tag at the end of the rename chain.
/// - For the board: the key of the board.
///
/// A ref names only a live node, unless the caller asks for tombstones (the undelete mutations do). A ref that names
/// no node gives ``KanbanError/notFound(type:reference:)``. A URI that does not parse also gives that error, because
/// the error catalog has no code for a ``NodeRefError``. A prefix of more than one ULID gives
/// ``KanbanError/ambiguousID(reference:matches:)`` with the short ids of the matches. A short id that more than one
/// ULID has (a merge can make such ULIDs) gives ``KanbanError/sharedShortID(reference:ids:)`` with the full ULIDs of
/// the matches (``KanbanError/ambiguity(of:among:)``).
///
/// ``anyLocalRef(for:)`` resolves a ref with no expected type, for `node(id:)` and `nodes(ids:)` (plan.md §4.1).
struct RefResolver: Sendable {
    /// The node types that a short form with no expected type can name, in the order of the tries. The first try
    /// takes the tasks and the comments together (``ulidTypes``), so that a `^short` form never names a slug. A slug
    /// of more than one type names the first type in this list; the full URI names each of the other nodes.
    private static let shortFormTypes: [PatchNodeType] = [.task, .board, .column, .actor, .tag]

    /// The node types whose local id is a ULID. A ULID form with no expected type resolves among all of them, so
    /// that a prefix of a task and a comment is ambiguous, and a canonical form wins over a prefix.
    private static let ulidTypes: Set<PatchNodeType> = [.task, .comment]

    /// The graph of the target board.
    let graph: Graph

    /// The current key of the target board, for example `github.com/swissarmyhammer/FoundationModelsKanban`.
    let boardKey: String

    /// Changes a forgiving ref to the stored ref of a node of the expected type.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it. White space at the two ends is ignored.
    ///   - type: The node type that the caller expects.
    ///   - acceptsRemote: `true` when the caller accepts a ref to a node of a different board, for example a
    ///     cross-board `dependsOn` edge. The resolver does not read the other board.
    ///   - includesTombstones: `true` when the ref can name a tombstone.
    /// - Returns: The local ref of the node, or the URI of a node of a different board.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no node of the type has the ref.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func storedRef(
        for reference: String,
        ofType type: PatchNodeType,
        acceptingRemote acceptsRemote: Bool = false,
        includingTombstones includesTombstones: Bool = false
    ) throws(KanbanError) -> StoredRef {
        let lookup = Lookup(reference: reference, type: type, includesTombstones: includesTombstones)
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NodeURI.hasScheme(atStartOf: text) else {
            return .local(try localRef(forKey: text, in: lookup))
        }
        let uri = try parsedURI(from: text, in: lookup)
        guard let ref = uri.localRef(inBoard: boardKey) else {
            return try remoteRef(to: uri, acceptingRemote: acceptsRemote, in: lookup)
        }
        return .local(try localRef(forKey: shortForm(of: ref), in: lookup))
    }

    /// Finds the node of any type that a forgiving ref names in this board, live or tombstoned (plan.md §3.3, rule 3).
    ///
    /// A full URI names the type of its node. A short form tries the node types of ``shortFormTypes`` in order, and
    /// the first type with a match gives the node.
    ///
    /// - Parameter reference: The ref as the caller wrote it. White space at the two ends is ignored.
    /// - Returns: The local ref of the node, or `nil` when no node has the ref, the URI does not parse, or the URI
    ///   names a node of a different board.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func anyLocalRef(for reference: String) throws(KanbanError) -> LocalRef? {
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NodeURI.hasScheme(atStartOf: text) else {
            return try anyLocalRef(forKey: text, writtenAs: reference)
        }
        guard let uri = try? NodeURI(parsing: text), let ref = uri.localRef(inBoard: boardKey) else {
            return nil
        }
        let lookup = Lookup(reference: reference, type: ref.nodeType, includesTombstones: true)
        return try candidateRef(forKey: shortForm(of: ref), in: lookup)
    }

    /// Checks that a short form is not a short id that two or more tasks or comments of this board have, live or
    /// tombstoned.
    ///
    /// A `^id` filter atom resolves its value among one task and its dependencies (``FilterEvaluator``), so it does
    /// not find two tasks with the same short id. The filter calls this check one time, before it tests the nodes.
    ///
    /// - Parameters:
    ///   - key: The short form, for example the value of a `^id` filter atom.
    ///   - reference: The ref as the caller wrote it, for the error message, for example `^ajv8v4t`.
    /// - Throws: ``KanbanError/sharedShortID(reference:ids:)`` when two or more tasks or comments have the short id.
    func checkShortIDIsUnique(_ key: String, writtenAs reference: String) throws(KanbanError) {
        try checkShortIDIsUnique(key, writtenAs: reference, among: Self.ulidTypes)
    }

    /// Finds the node of any type that a short form names, live or tombstoned.
    ///
    /// - Parameters:
    ///   - key: The short form, without white space at the two ends.
    ///   - reference: The ref as the caller wrote it, for the error message.
    /// - Returns: The local ref of the node of the first type of ``shortFormTypes`` that has the short form, or `nil`
    ///   when no node has it.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the short form is a prefix of more than one
    ///   ULID.
    private func anyLocalRef(forKey key: String, writtenAs reference: String) throws(KanbanError) -> LocalRef? {
        for type in Self.shortFormTypes {
            let lookup = Lookup(reference: reference, type: type, includesTombstones: true, ulidTypes: Self.ulidTypes)
            if let ref = try candidateRef(forKey: key, in: lookup) {
                return ref
            }
        }
        return nil
    }
}

// MARK: - Lookup

extension RefResolver {
    /// One resolve: the ref as the caller wrote it, and what the caller expects it to name.
    private struct Lookup {
        /// The ref as the caller wrote it, for the error message.
        let reference: String

        /// The node type that the caller expects.
        let type: PatchNodeType

        /// `true` when the ref can name a tombstone.
        let includesTombstones: Bool

        /// The node types of the candidates of a ULID form.
        let ulidTypes: Set<PatchNodeType>

        /// Makes a resolve.
        ///
        /// - Parameters:
        ///   - reference: The ref as the caller wrote it.
        ///   - type: The node type that the caller expects.
        ///   - includesTombstones: `true` when the ref can name a tombstone.
        ///   - ulidTypes: The node types of the candidates of a ULID form, or `nil` for the expected type only.
        init(
            reference: String,
            type: PatchNodeType,
            includesTombstones: Bool,
            ulidTypes: Set<PatchNodeType>? = nil
        ) {
            self.reference = reference
            self.type = type
            self.includesTombstones = includesTombstones
            self.ulidTypes = ulidTypes ?? [type]
        }

        /// The `NOT_FOUND` error of the ref.
        var notFound: KanbanError {
            .notFound(type: type, reference: reference)
        }
    }

    /// Gives the short form of a local ref of this board: its local id. The board ref has no local id, so its short
    /// form is the key of the board.
    ///
    /// - Parameter ref: The local ref.
    /// - Returns: The short form.
    private func shortForm(of ref: LocalRef) -> String {
        ref.localID ?? boardKey
    }

    /// Reads a full URI, and checks that it names a node of the expected type.
    ///
    /// - Parameters:
    ///   - text: The URI text, without white space at the two ends.
    ///   - lookup: The resolve.
    /// - Returns: The URI.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the text is not a valid URI, or when the URI names a
    ///   node of a different type.
    private func parsedURI(from text: String, in lookup: Lookup) throws(KanbanError) -> NodeURI {
        let uri: NodeURI
        do {
            uri = try NodeURI(parsing: text)
        } catch {
            throw lookup.notFound
        }
        guard uri.ref.nodeType == lookup.type else {
            throw lookup.notFound
        }
        return uri
    }

    /// Gives the stored ref of a URI to a node of a different board.
    ///
    /// The resolver does not read the other board, so it does not check that the node exists. A read of the
    /// dependency finds the other board with the ``BoardLocator`` (plan.md §6.6). A target in a board that the scan
    /// cannot find counts as not done.
    ///
    /// - Parameters:
    ///   - uri: The URI, with a key that is not the key of this board.
    ///   - acceptsRemote: `true` when the caller accepts a ref to a node of a different board.
    ///   - lookup: The resolve.
    /// - Returns: The remote ref.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the caller does not accept a cross-board ref.
    private func remoteRef(
        to uri: NodeURI,
        acceptingRemote acceptsRemote: Bool,
        in lookup: Lookup
    ) throws(KanbanError) -> StoredRef {
        guard acceptsRemote else {
            throw lookup.notFound
        }
        return .remote(uri)
    }

    /// Finds the local ref of a short form in this board.
    ///
    /// - Parameters:
    ///   - key: The short form: a ULID form, a slug or a name, or the key of the board.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the node.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no node of the type has the short form.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the short form is a prefix of more than one ULID.
    private func localRef(forKey key: String, in lookup: Lookup) throws(KanbanError) -> LocalRef {
        guard let ref = try candidateRef(forKey: key, in: lookup) else {
            throw lookup.notFound
        }
        return ref
    }

    /// Finds the node of the expected type that a short form names.
    ///
    /// - Parameters:
    ///   - key: The short form.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the node, or `nil` when no node of the type has the short form.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the short form is a prefix of more than one
    ///   ULID.
    private func candidateRef(forKey key: String, in lookup: Lookup) throws(KanbanError) -> LocalRef? {
        switch lookup.type {
        case .board:
            return key == boardKey ? ref(of: .board, in: lookup) : nil
        case .column:
            return ref(of: .column(slug: Slug.normalizedText(of: key)), in: lookup)
        case .actor:
            return ref(of: .actor(slug: Slug.normalizedText(of: key)), in: lookup)
        case .tag:
            return tagRef(named: key, in: lookup)
        case .task, .comment:
            return try ulidRef(for: key, in: lookup)
        }
    }

    /// Finds the tag that a tag name names, after the rename redirect.
    ///
    /// - Parameters:
    ///   - name: The slug or the tag name.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the tag at the end of the rename chain, or `nil` when the name gives an empty
    ///   slug, the graph does not have the tag, or the chain ends with no tag or at a tombstone that the lookup does
    ///   not accept.
    private func tagRef(named name: String, in lookup: Lookup) -> LocalRef? {
        guard
            let slug = try? TagName(normalizing: name).slug,
            let slot = graph.slot(for: .tag(slug: slug.value)),
            let target = graph.renameTarget(ofTagAt: slot)
        else {
            return nil
        }
        return ref(at: target, in: lookup)
    }

    /// Finds the task or the comment that a ULID form names.
    ///
    /// The candidates are the nodes of the ULID types of the lookup that the lookup accepts, in slot order. Thus, a
    /// tombstone does not make a prefix ambiguous, unless the lookup accepts tombstones.
    ///
    /// - Parameters:
    ///   - key: The full ULID, the short id, either of these with a leading ``ShortID/sigil``, or a ULID prefix.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the node, or `nil` when no candidate matches.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the key is a prefix of more than one candidate.
    ///   ``KanbanError/sharedShortID(reference:ids:)`` when the key is a short id that two or more nodes of the ULID
    ///   types have, live or tombstoned (``checkShortIDIsUnique(_:writtenAs:among:)``), or when two or more of the
    ///   candidates that a prefix matches have the same short id.
    private func ulidRef(for key: String, in lookup: Lookup) throws(KanbanError) -> LocalRef? {
        try checkShortIDIsUnique(key, writtenAs: lookup.reference, among: lookup.ulidTypes)
        let candidates = graph.allSlots
            .compactMap { slot in ref(at: slot, in: lookup) }
            .filter { candidate in lookup.ulidTypes.contains(candidate.nodeType) }
        switch ShortID.resolve(key, among: candidates.compactMap(\.localID)) {
        case .found(let ulid):
            return candidates.first { candidate in candidate.localID == ulid }
        case .notFound:
            return nil
        case .ambiguous(let ulids):
            throw .ambiguity(of: lookup.reference, among: ulids)
        }
    }

    /// Checks that no two nodes of some types have the short id that a ULID form names.
    ///
    /// The check reads each node of the types, live or tombstoned, also when the lookup does not accept tombstones.
    /// Thus, a short id that a live node and a tombstone share names no node (plan.md §3.2: a short id is a unique
    /// ULID prefix).
    ///
    /// - Parameters:
    ///   - key: The ULID form. Only a short id, with or without a leading ``ShortID/sigil``, can fail the check.
    ///   - reference: The ref as the caller wrote it, for the error message.
    ///   - types: The node types whose local id is a ULID that the form can name.
    /// - Throws: ``KanbanError/sharedShortID(reference:ids:)`` with the full ULIDs, in slot order, when two or more
    ///   nodes have the short id.
    private func checkShortIDIsUnique(
        _ key: String,
        writtenAs reference: String,
        among types: Set<PatchNodeType>
    ) throws(KanbanError) {
        let ulids = graph.allSlots
            .compactMap { slot in graph.node(at: slot)?.ref }
            .filter { ref in types.contains(ref.nodeType) }
            .compactMap(\.localID)
        let owners = ShortID.ulids(withShortIDOf: key, among: ulids)
        guard owners.count < 2 else {
            throw .sharedShortID(reference: reference, ids: owners)
        }
    }

    /// Gives a local ref when the graph has its node and the lookup accepts the node.
    ///
    /// - Parameters:
    ///   - localRef: The local ref.
    ///   - lookup: The resolve.
    /// - Returns: The local ref, or `nil` when the graph does not have the node or the lookup does not accept it.
    private func ref(of localRef: LocalRef, in lookup: Lookup) -> LocalRef? {
        graph.slot(for: localRef).flatMap { slot in ref(at: slot, in: lookup) }
    }

    /// Gives the local ref of the node in a slot when the lookup accepts the node.
    ///
    /// - Parameters:
    ///   - slot: A slot of the graph.
    ///   - lookup: The resolve.
    /// - Returns: The local ref, or `nil` when the slot holds no node, or holds a tombstone and the lookup does not
    ///   accept tombstones.
    private func ref(at slot: Int, in lookup: Lookup) -> LocalRef? {
        guard let node = graph.node(at: slot), lookup.includesTombstones || !node.state.fields.isDeleted else {
            return nil
        }
        return node.ref
    }
}
