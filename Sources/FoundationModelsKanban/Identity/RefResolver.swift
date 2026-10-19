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
/// - For a task only, after each ULID form: the slug of the title, or a title that gives the slug, for example
///   `fix-login-bug` (divergence.md C3, E4). A title slug that more than one task has names the first match, the same
///   as a shared short id, with a ``sharedTitleSlugWarningCode`` warning.
/// - For a column or an actor: the slug, or a name that gives the slug (``Slug/normalizedText(of:)``).
/// - For a tag: the slug, or a tag name that gives the slug (``TagName``). The resolve then follows the rename
///   redirect (plan.md §6.2), so a ref to an old slug gives the tag at the end of the rename chain.
/// - For the board: the key of the board. The host of the key ignores case (``BoardKey/normalizedText(of:)``).
/// - The stored local form `<type>/<id>` that the log stores (``LocalRef``, divergence.md R18), for example
///   `task/01K6Z3…`, `column/todo`, or `tag/bug`. It names a node of this board, the same as a URI with the key of
///   this board, and the `<id>` part takes each form above of that type, for example `task/^short`. A type that is
///   not the expected type gives `NOT_FOUND`, the same as a URI of a different type.
///
/// A ref names only a live node, unless the caller asks for tombstones (the undelete mutations do). A ref that names
/// no node gives ``KanbanError/notFound(type:reference:)``. A URI that does not parse also gives that error, because
/// the error catalog has no code for a ``NodeRefError``. A ULID prefix of more than one ULID gives
/// ``KanbanError/ambiguousID(reference:matches:)`` with the id and the title of each match (divergence.md P5). A
/// short id that more than one ULID has (a merge can make such ULIDs) names the first match: a live node comes before
/// a tombstone, then the lowest ULID. The pick adds a ``sharedShortIDWarningCode`` warning to the collector of the
/// run (``ResolverWarnings``), with the ULIDs of the matches (divergence.md Q20).
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

    /// The code of the warning of a short id that more than one node has, in `extensions.warnings` (divergence.md
    /// Q20). The resolve names the first match and gives this warning.
    static let sharedShortIDWarningCode = "SHARED_SHORT_ID"

    /// The code of the warning of a title slug that more than one task has, in `extensions.warnings` (divergence.md
    /// C3). The resolve names the first match and gives this warning.
    static let sharedTitleSlugWarningCode = "SHARED_TITLE_SLUG"

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
        switch try target(of: reference, in: lookup) {
        case .shortForm(let key), .sameBoard(let key, _):
            return .local(try localRef(forKey: key, in: lookup))
        case .otherBoard(let uri):
            return try remoteRef(to: uri, acceptingRemote: acceptsRemote, in: lookup)
        }
    }

    /// Changes the id of a node that a mutation can make to the short form of the node in this board (plan.md §3.2).
    ///
    /// A full URI gets the same checks as in ``storedRef(for:ofType:acceptingRemote:includingTombstones:)``: the URI
    /// must parse, name a node of the expected type, and have the key of this board. Then the URI gives its local id.
    /// The stored local form `<type>/<id>` must name the expected type, and gives its `<id>` part. The graph does not
    /// need the node, so that the mutation can make it. A short form stays as the caller wrote it. The caller applies
    /// its slug rule to the result.
    ///
    /// - Parameters:
    ///   - reference: The id as the caller wrote it. White space at the two ends of a URI or of a stored local form
    ///     is ignored.
    ///   - type: The node type that the mutation makes.
    /// - Returns: The local id of the URI, the `<id>` part of the stored local form, or the reference when it is a
    ///   short form.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the URI does not parse, the URI or the stored local
    ///   form names a node of a different type, or the URI has the key of a different board.
    func newNodeKey(for reference: String, ofType type: PatchNodeType) throws(KanbanError) -> String {
        let lookup = Lookup(reference: reference, type: type, includesTombstones: false)
        switch try target(of: reference, in: lookup) {
        case .shortForm:
            return reference
        case .sameBoard(let key, _):
            return key
        case .otherBoard:
            throw lookup.notFound
        }
    }

    /// Finds the node of any type that a forgiving ref names in this board, live or tombstoned (plan.md §3.3, rule 3).
    ///
    /// A full URI and the stored local form `<type>/<id>` name the type of their node. A short form tries the node
    /// types of ``shortFormTypes`` in order, and the first type with a match gives the node. The title slug of a task
    /// comes last, after each other slug, so a column slug that is the same text gives the column (divergence.md E4).
    ///
    /// - Parameter reference: The ref as the caller wrote it. White space at the two ends is ignored.
    /// - Returns: The local ref of the node, or `nil` when no node has the ref, the URI does not parse, or the URI
    ///   names a node of a different board.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func anyLocalRef(for reference: String) throws(KanbanError) -> LocalRef? {
        switch target(of: reference) {
        case .shortForm(let key)?:
            return try anyLocalRef(forKey: key, writtenAs: reference)
        case .sameBoard(let key, let type)?:
            let lookup = Lookup(reference: reference, type: type, includesTombstones: true)
            return try candidateRef(forKey: key, in: lookup)
        case .otherBoard?, nil:
            return nil
        }
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
            let lookup = Lookup(
                reference: reference,
                type: type,
                includesTombstones: true,
                ulidTypes: Self.ulidTypes,
                matchesTitleSlug: false
            )
            if let ref = try candidateRef(forKey: key, in: lookup) {
                return ref
            }
        }
        return titleSlugRef(for: key, in: Lookup(reference: reference, type: .task, includesTombstones: true))
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

        /// `true` when a task ref that is no ULID form can name a task by the slug of its title (divergence.md C3).
        let matchesTitleSlug: Bool

        /// Makes a resolve.
        ///
        /// - Parameters:
        ///   - reference: The ref as the caller wrote it.
        ///   - type: The node type that the caller expects.
        ///   - includesTombstones: `true` when the ref can name a tombstone.
        ///   - ulidTypes: The node types of the candidates of a ULID form, or `nil` for the expected type only.
        ///   - matchesTitleSlug: `true` when a task ref that is no ULID form can name a task by the slug of its
        ///     title. A resolve with no expected type sets `false`, and tries the title slug after each other slug
        ///     (divergence.md E4).
        init(
            reference: String,
            type: PatchNodeType,
            includesTombstones: Bool,
            ulidTypes: Set<PatchNodeType>? = nil,
            matchesTitleSlug: Bool = true
        ) {
            self.reference = reference
            self.type = type
            self.includesTombstones = includesTombstones
            self.ulidTypes = ulidTypes ?? [type]
            self.matchesTitleSlug = matchesTitleSlug
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

    /// Gives the `<id>` part of a ref in the stored local form `<type>/<id>` of one node type (``LocalRef``,
    /// divergence.md R18). The type segment ignores case, and the `<id>` part has no white space at the two ends.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it.
    ///   - type: The node type that the type segment must name.
    /// - Returns: The `<id>` part, or `nil` when the ref is not in the stored local form of that node type.
    static func localID(inStoredLocalForm reference: String, ofType type: PatchNodeType) -> String? {
        guard case .localRef(let found, let key) = RefText(reference), found == type else {
            return nil
        }
        return key
    }

    /// The text of a ref without white space at the two ends, sorted by its form.
    private enum RefText {
        /// A short form: a ULID form, a slug or a name, or the key of the board.
        case shortForm(String)

        /// The text of a full `kanban://` URI.
        case uri(String)

        /// The stored local form `<type>/<id>`, as the log stores a ref to a node of the same board (``LocalRef``,
        /// divergence.md R18): the node type, and the `<id>` part as a short form of that type.
        case localRef(type: PatchNodeType, key: String)

        /// Sorts a ref by its form.
        ///
        /// - Parameter reference: The ref as the caller wrote it.
        init(_ reference: String) {
            let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            if NodeURI.hasScheme(atStartOf: text) {
                self = .uri(text)
            } else if let (type, key) = Self.localRefParts(of: text) {
                self = .localRef(type: type, key: key)
            } else {
                self = .shortForm(text)
            }
        }

        /// Splits the stored local form `<type>/<id>` at its first ``LocalRef/separator``.
        ///
        /// The type segment ignores case (``PatchNodeType/init(pathSegment:)``). The `<id>` part is all the text after
        /// the first separator, without white space at the two ends. A board key does not start with a node type (its
        /// first segment is a host or ``BoardKey/localHost``), so a board key stays a short form. The bare text
        /// `board` has no separator, so it also stays a short form, and a mutation that makes a column, an actor, or a
        /// tag with that id still gives the reserved slug error.
        ///
        /// - Parameter text: The ref without white space at the two ends.
        /// - Returns: The node type and the `<id>` part, or `nil` when the text has no separator or the text before
        ///   the first separator is not a node type.
        private static func localRefParts(of text: String) -> (type: PatchNodeType, key: String)? {
            guard
                let separatorIndex = text.firstIndex(of: LocalRef.separator),
                let type = PatchNodeType(pathSegment: String(text[..<separatorIndex]))
            else {
                return nil
            }
            let key = text[text.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (type, key)
        }
    }

    /// The node that a ref names, as this board sees it.
    private enum RefTarget {
        /// A short form, without white space at the two ends.
        case shortForm(String)

        /// A URI with the key of this board, or the stored local form `<type>/<id>`, by the short form and the node
        /// type of its node.
        case sameBoard(key: String, type: PatchNodeType)

        /// A URI with the key of a different board.
        case otherBoard(NodeURI)

        /// Tells if the target can name a node of a type. A short form can name a node of each type. A URI or a
        /// stored local form names a node of its own type only.
        ///
        /// - Parameter type: The node type that the caller expects.
        /// - Returns: `true` when the target is a short form, or a URI or a stored local form that names a node of the
        ///   type.
        func canName(_ type: PatchNodeType) -> Bool {
            switch self {
            case .shortForm:
                return true
            case .sameBoard(_, let nodeType):
                return nodeType == type
            case .otherBoard(let uri):
                return uri.ref.nodeType == type
            }
        }
    }

    /// Sorts a ref into a short form, a node of this board, or a URI of a different board. This is the only parse of
    /// a URI and the only check of its board key in the resolver.
    ///
    /// The stored local form `<type>/<id>` names a node of this board, the same as a URI with the key of this board.
    /// It never names a node of a different board.
    ///
    /// - Parameter reference: The ref as the caller wrote it. White space at the two ends is ignored.
    /// - Returns: The target of the ref, or `nil` when the ref is a URI that does not parse. The graph does not need
    ///   the node.
    private func target(of reference: String) -> RefTarget? {
        switch RefText(reference) {
        case .shortForm(let key):
            return .shortForm(key)
        case .localRef(let type, let key):
            return .sameBoard(key: key, type: type)
        case .uri(let text):
            guard let uri = try? NodeURI(parsing: text) else {
                return nil
            }
            guard let key = localKey(forURI: uri) else {
                return .otherBoard(uri)
            }
            return .sameBoard(key: key, type: uri.ref.nodeType)
        }
    }

    /// Sorts a ref of the expected type into a short form, a node of this board, or a URI of a different board.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it. White space at the two ends is ignored.
    ///   - lookup: The resolve.
    /// - Returns: The target of the ref. The graph does not need the node.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the ref is a URI that does not parse, or a URI or a
    ///   stored local form that names a node of a different type.
    private func target(of reference: String, in lookup: Lookup) throws(KanbanError) -> RefTarget {
        guard let target = target(of: reference), target.canName(lookup.type) else {
            throw lookup.notFound
        }
        return target
    }

    /// Gives the short form of the node of a URI, when the URI has the key of this board.
    ///
    /// A URI with any name of this board (``boardNames``) names a node of this board: the git key, a board ID, or an
    /// old name (divergence.md M9). The stored ref is then a local ref, so it never holds a name of its own board.
    ///
    /// - Parameter uri: The URI.
    /// - Returns: The short form, or `nil` when the URI has the key of a different board.
    private func localKey(forURI uri: NodeURI) -> String? {
        boardNames.contains(uri.boardKey) ? shortForm(of: uri.ref) : nil
    }

    /// The names of this board: the current key, and the board IDs and the old names of the board node of the graph
    /// (divergence.md M9).
    private var boardNames: BoardNames {
        BoardNames(key: boardKey, board: graph.boardNode)
    }

    /// Gives the stored ref of a URI to a node of a different board.
    ///
    /// The resolver does not read the other board, so it does not check that the node exists: a ref to a missing
    /// task, or to a board that the scan cannot find, is accepted (divergence.md Q3 as P3 changed it). The task write
    /// checks the target against the related boards of the run and gives a warning when it cannot resolve
    /// (``DependencyWarnings``). A read of the dependency finds the other board with the ``BoardLocator`` (plan.md
    /// §6.6). A target that no loaded board has counts as not done, and `unresolvedDependsOn` lists it.
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
            return boardNames.contains(key) ? ref(of: .board, in: lookup) : nil
        case .column:
            return ref(of: .column(slug: Slug.normalizedText(of: key)), in: lookup)
        case .actor:
            return ref(of: .actor(slug: Slug.normalizedText(of: key)), in: lookup)
        case .tag:
            return tagRef(named: key, in: lookup)
        case .task:
            return try ulidRef(for: key, in: lookup) ?? titleSlugRef(for: key, in: lookup)
        case .comment:
            return try ulidRef(for: key, in: lookup)
        }
    }

    /// Finds the task whose title has the slug of a short form (divergence.md C3).
    ///
    /// A title slug that more than one task has names the first match, with the same order and the same kind of
    /// warning as a short id that more than one task has (``firstMatch(among:writtenAs:sharing:)``).
    ///
    /// - Parameters:
    ///   - key: The short form: the title slug, or a title that gives the slug.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the task, or `nil` when the lookup does not match title slugs, or no task that the
    ///   lookup accepts has the title slug.
    private func titleSlugRef(for key: String, in lookup: Lookup) -> LocalRef? {
        guard lookup.matchesTitleSlug else {
            return nil
        }
        let owners = graph.taskSlots(withTitleSlugOf: key).compactMap { slot in ref(at: slot, in: lookup) }
        guard owners.count > 1 else {
            return owners.first
        }
        return firstMatch(among: owners, writtenAs: lookup.reference, sharing: .titleSlug)
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
    /// tombstone does not make a prefix ambiguous, and is not a match of a short id, unless the lookup accepts
    /// tombstones.
    ///
    /// - Parameters:
    ///   - key: The full ULID, the short id, either of these with a leading ``ShortID/sigil``, or a ULID prefix.
    ///   - lookup: The resolve.
    /// - Returns: The local ref of the node, or `nil` when no candidate matches. A short id of more than one candidate
    ///   gives the first match (``firstMatch(among:writtenAs:sharing:)``).
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the key is a ULID prefix of more than one
    ///   candidate.
    private func ulidRef(for key: String, in lookup: Lookup) throws(KanbanError) -> LocalRef? {
        let candidates = graph.allSlots
            .compactMap { slot in ref(at: slot, in: lookup) }
            .filter { candidate in lookup.ulidTypes.contains(candidate.nodeType) }
        switch ShortID.resolve(key, among: candidates.compactMap(\.localID)) {
        case .found(let ulid):
            return candidates.first { candidate in candidate.localID == ulid }
        case .notFound:
            return nil
        case .shared(let ulids):
            let owners = Self.refs(withULIDs: ulids, among: candidates)
            return firstMatch(among: owners, writtenAs: lookup.reference, sharing: .shortID)
        case .ambiguous(let ulids):
            throw .ambiguousID(reference: lookup.reference, matches: ambiguousMatches(of: ulids, among: candidates))
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

// MARK: - More than one match

extension RefResolver {
    /// Gives the candidates that have some ULIDs, in the order of the candidates.
    ///
    /// - Parameters:
    ///   - ulids: The ULID texts that a resolve matched.
    ///   - candidates: The local refs of the candidates of the resolve.
    /// - Returns: The local ref of each candidate whose local id is one of the ULIDs.
    private static func refs(withULIDs ulids: [String], among candidates: [LocalRef]) -> [LocalRef] {
        let matched = Set(ulids)
        return candidates.filter { candidate in candidate.localID.map(matched.contains) ?? false }
    }

    /// The form of a ref that more than one node can have: a short id (divergence.md Q20), or the slug of a task
    /// title (divergence.md C3).
    private enum SharedForm {
        /// A short id that more than one ULID has.
        case shortID

        /// A title slug that more than one task has.
        case titleSlug

        /// The name of the form in the warning, for example `short id`.
        var name: String {
            switch self {
            case .shortID: "short id"
            case .titleSlug: "title slug"
            }
        }

        /// The name of each match in the warning, for example `id`.
        var matchName: String {
            switch self {
            case .shortID: "id"
            case .titleSlug: "task"
            }
        }

        /// The code of the warning.
        var warningCode: String {
            switch self {
            case .shortID: RefResolver.sharedShortIDWarningCode
            case .titleSlug: RefResolver.sharedTitleSlugWarningCode
            }
        }
    }

    /// Picks the first match of a ref that more than one node has, and adds a warning that lists the matches
    /// (divergence.md Q20 and C3).
    ///
    /// The order is the same on each call: a live node comes before a tombstone, then the lowest ULID
    /// (``precedes(_:_:)``). The warning goes to the collector of the run (``ResolverWarnings/current``), so that the
    /// agent learns that the call used one of more nodes, and how to name a different one.
    ///
    /// - Parameters:
    ///   - owners: The local refs of the nodes that have the ref.
    ///   - reference: The ref as the caller wrote it, for the warning.
    ///   - form: The form of the ref that the nodes share.
    /// - Returns: The first match, or `nil` when the list is empty.
    private func firstMatch(
        among owners: [LocalRef],
        writtenAs reference: String,
        sharing form: SharedForm
    ) -> LocalRef? {
        let ordered = owners.sorted(by: precedes)
        guard let first = ordered.first else {
            return nil
        }
        let warning = Self.sharedRefWarning(writtenAs: reference, sharing: form, picking: first, of: ordered)
        ResolverWarnings.current?.add(warning)
        return first
    }

    /// Tells if a node comes before a different node in the order of the matches of a shared short id: a live node
    /// comes before a tombstone, then the lowest ULID.
    ///
    /// - Parameters:
    ///   - lhs: The local ref of the first node.
    ///   - rhs: The local ref of the second node.
    /// - Returns: `true` when the first node comes before the second node.
    private func precedes(_ lhs: LocalRef, _ rhs: LocalRef) -> Bool {
        let (lhsIsTombstone, rhsIsTombstone) = (isTombstone(lhs), isTombstone(rhs))
        guard lhsIsTombstone == rhsIsTombstone else {
            return rhsIsTombstone
        }
        return (lhs.localID ?? "") < (rhs.localID ?? "")
    }

    /// Tells if the node of a local ref is a tombstone.
    ///
    /// - Parameter ref: The local ref of a node of the graph.
    /// - Returns: `true` when the graph has the node and the node is deleted.
    private func isTombstone(_ ref: LocalRef) -> Bool {
        graph.slot(for: ref).flatMap(graph.node(at:))?.state.fields.isDeleted ?? false
    }

    /// Makes the warning of the pick of the first match of a shared short id or title slug.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it.
    ///   - form: The form of the ref that the matches share.
    ///   - first: The local ref of the first match.
    ///   - ordered: The local refs of the matches, in the order of the pick.
    /// - Returns: The warning, with the ULID of each match.
    private static func sharedRefWarning(
        writtenAs reference: String,
        sharing form: SharedForm,
        picking first: LocalRef,
        of ordered: [LocalRef]
    ) -> ResponseWarning {
        let ids = ordered.compactMap(\.localID).joined(separator: KanbanError.listSeparator)
        let message = "The \(form.name) \"\(reference)\" matches more than one \(form.matchName): \(ids). The call "
            + "used \(first.localID ?? ""): a live node comes first, and then the lowest id. Send the full id to use "
            + "a different node."
        return ResponseWarning(message: message, code: form.warningCode)
    }

    /// Gives the matches of an ambiguous ULID prefix for its `AMBIGUOUS_ID` error (divergence.md P5).
    ///
    /// Each match gives the id that names it alone in the lookup: the short id with a leading ``ShortID/sigil``, or
    /// the full ULID when a different candidate has the same short id (``ShortID/collisions(among:)``). A task gives
    /// its title.
    ///
    /// - Parameters:
    ///   - ulids: The ULID texts that the prefix matches, in the order of the candidates.
    ///   - candidates: The local refs of the candidates of the resolve.
    /// - Returns: The matches, in the order of the ULIDs.
    private func ambiguousMatches(of ulids: [String], among candidates: [LocalRef]) -> [KanbanError.AmbiguousMatch] {
        let sharedShortIDs = ShortID.collisions(among: candidates.compactMap(\.localID))
        return Self.refs(withULIDs: ulids, among: candidates).compactMap { ref in
            ref.localID.map { ulid in
                let shortID = ShortID(ofULIDString: ulid)
                let id = sharedShortIDs[shortID] == nil ? "\(ShortID.sigil)\(shortID.value)" : ulid
                return KanbanError.AmbiguousMatch(id: id, title: title(of: ref))
            }
        }
    }

    /// Gives the title of the task of a local ref.
    ///
    /// - Parameter ref: The local ref of a node of the graph.
    /// - Returns: The title, or `nil` when the node is not a task, for example a comment.
    private func title(of ref: LocalRef) -> String? {
        graph.slot(for: ref).flatMap { slot in graph.node(at: slot, as: TaskNode.self) }?.title
    }
}

// MARK: - Title slugs

extension Graph {
    /// Finds each task whose title has the slug of a name, live or tombstoned (divergence.md Q25, C3).
    ///
    /// The resolve of a task ref and the `^` filter atom both read it, so that the two agree on which tasks have a
    /// title slug. The slug rule is ``Slug/normalizedText(of:)``, so `Fix login bug`, `fix-login-bug`, and
    /// `^fix-login-bug` all give `fix-login-bug`.
    ///
    /// - Parameter name: The title slug, or a title that gives the slug.
    /// - Returns: The slots of the tasks, in slot order. A name that gives an empty slug gives no slots.
    func taskSlots(withTitleSlugOf name: String) -> [Int] {
        let slug = Slug.normalizedText(of: name)
        guard !slug.isEmpty else {
            return []
        }
        return allSlots.filter { slot in
            node(at: slot, as: TaskNode.self).map { task in Slug.normalizedText(of: task.title) == slug } ?? false
        }
    }
}
