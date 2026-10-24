import Foundation

/// The name check of the filter agent (divergence.md §17, "The loop"): a filter passes only when it parses and each
/// name in it names a node of the board.
///
/// The check reads each `#tag`, `@actor`, and `%column` atom, by name or by a URL of this board, with the name
/// resolution of the task list (``FilterNames``). A tag passes when it is a virtual tag (``VirtualTag``) or a live tag,
/// after the rename redirect. An actor passes when it is a live actor of the board, an actor of a different board
/// that a task has as its assignee, or the slug of the caller actor, also when the caller is not yet an actor of the
/// board: then "my tasks" is a filter that selects no task. A column passes when it is a live column. A URL of a
/// different board, a `^id` atom, and a `~type` atom pass: the check does not read them. The board has no projects, so
/// a `$project` atom gives the parse error of the removed sigil.
///
/// A name that names nothing gives `INVALID_FILTER` at the atom, with the specific message, for example
/// ``"no tag named `urgnt`; the nearest tag is `urgent`"``, and the filter with a name of the board in place of the
/// atom as the example. The filter of a task list does not use this check: there, a name that names nothing gives
/// no task.
struct FilterNameCheck {
    /// The largest edit distance from a name to a name of the board that the message gives as the nearest name.
    static let nearDistanceLimit = 2

    /// The name resolution of the board.
    private let names: FilterNames

    /// The slug of the session actor of the call, or `nil` when the call has no caller actor. The vocabulary tells the
    /// model to write `@<slug>` for "me" (``FilterVocabulary``), so this slug passes also when the caller is not yet an
    /// actor of the board.
    private let callerSlug: String?

    /// Makes the name check of one board.
    ///
    /// - Parameters:
    ///   - readiness: The readiness of the tasks of the board. It holds the graph.
    ///   - boardKey: The current key of the board. A URL with this key names a node of the board.
    ///   - caller: The session actor of the call, or `nil` when the call has no caller actor.
    init(over readiness: Readiness, inBoard boardKey: String, for caller: SessionActor?) {
        names = FilterNames(readiness: readiness, boardKey: boardKey)
        callerSlug = caller?.ref.localID
    }

    /// Parses a filter, and checks that each name in it names a node of the board.
    ///
    /// - Parameter filter: The text of the filter, for example `#bug @alice !#DONE`.
    /// - Returns: The parsed filter.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter does not parse, or at
    ///   the first atom in the text whose name names nothing.
    @discardableResult
    func check(_ filter: String) throws(KanbanError) -> FilterExpr {
        let parsed = try ParsedFilter(parsing: filter)
        let firstUnknown = parsed.atoms.lazy.compactMap { atom in unknownNameError(at: atom, in: filter) }.first
        guard let firstUnknown else {
            return parsed.expression
        }
        throw firstUnknown.kanbanError(in: filter)
    }

    /// Gives the error of an atom whose name names nothing.
    ///
    /// - Parameters:
    ///   - atom: The atom, with its text in the filter.
    ///   - filter: The full filter.
    /// - Returns: The error at the atom, or `nil` when the check does not read the atom or its name names a node.
    private func unknownNameError(at atom: FilterAtomText, in filter: String) -> FilterSyntaxError? {
        guard case .local(let name)? = names.target(of: atom.value, for: atom.kind),
            !isKnown(name, as: atom.kind),
            let type = atom.kind.bareURLType
        else {
            return nil
        }
        let nearest = Self.nearest(to: Slug.normalizedText(of: name), among: candidates(for: atom.kind))
        let replacement = nearest.map { found in "\(atom.kind.sigil)\(found.candidate.name)" } ?? atom.kind.example
        let problem = FilterSyntaxError.Problem.unknownName(
            type: type,
            name: name,
            nearestName: nearest.flatMap { found in found.isNear ? found.candidate.name : nil },
            correctedFilter: filter.replacingCharacters(in: atom.text.startIndex..<atom.text.endIndex, with: replacement)
        )
        return FilterSyntaxError(problem: problem, at: atom.text)
    }

    /// Tells if a name of an atom names a node of the board, with the rules of the filter evaluator.
    ///
    /// - Parameters:
    ///   - name: The name as the atom writes it, or the local id of its URL.
    ///   - kind: The kind of the atom.
    /// - Returns: `true` when the name names a node, and for a `^` or a `~` atom, which the check does not read.
    private func isKnown(_ name: String, as kind: FilterAtomKind) -> Bool {
        switch kind {
        case .tag:
            VirtualTag(named: name) != nil || names.liveTagSlot(named: name) != nil
        case .assignee:
            !names.liveSlots(of: ActorNode.self, named: name).isEmpty || names.hasRemoteAssignee(named: name)
                || isCallerSlug(name)
        case .column:
            !names.liveSlots(of: ColumnNode.self, named: name).isEmpty
        case .ref, .type:
            true
        }
    }

    /// Tells if a name of an `@` atom is the slug of the caller actor.
    ///
    /// - Parameter name: The name as the atom writes it, or the local id of its URL, in any case.
    /// - Returns: `true` when the call has a caller actor and the slug of the name is its slug.
    private func isCallerSlug(_ name: String) -> Bool {
        callerSlug == Slug.normalizedText(of: name)
    }

    /// Gives the names of the board that an atom of a kind can name, in a stable order.
    ///
    /// - Parameter kind: The kind of the atom.
    /// - Returns: The live nodes of the kind in slug order. For a tag, the virtual tags come after the real tags.
    private func candidates(for kind: FilterAtomKind) -> [NameCandidate] {
        switch kind {
        case .tag:
            NameCandidate.ofNodes(names.liveNodes(of: TagNode.self)) + VirtualTag.allCases.map(NameCandidate.init)
        case .assignee:
            NameCandidate.ofNodes(names.liveNodes(of: ActorNode.self))
        case .column:
            NameCandidate.ofNodes(names.liveNodes(of: ColumnNode.self))
        case .ref, .type:
            []
        }
    }

    /// Finds the name of the board with the smallest edit distance to a name.
    ///
    /// - Parameters:
    ///   - key: The slug of the name.
    ///   - candidates: The names of the board, in their stable order. Of two names at the same distance, the first one
    ///     wins.
    /// - Returns: The nearest name, or `nil` when there is no candidate.
    private static func nearest(to key: String, among candidates: [NameCandidate]) -> NearestName? {
        candidates
            .map { candidate in NearestName(candidate: candidate, key: key) }
            .min { first, second in first.distance < second.distance }
    }
}

// MARK: - Candidates

/// One name of the board that an atom can name.
private struct NameCandidate {
    /// The name as an atom writes it: the slug of a node, or the name of a virtual tag.
    let name: String

    /// The slugs that the edit distance reads: the slug of the node and the slug of its name.
    let keys: [String]

    /// Makes the candidate of a virtual tag.
    ///
    /// - Parameter virtualTag: The virtual tag.
    init(_ virtualTag: VirtualTag) {
        name = virtualTag.rawValue
        keys = [virtualTag.rawValue.lowercased()]
    }

    /// Makes the candidate of a node.
    ///
    /// - Parameter node: The state of the node.
    private init(node: some SlugNamedState) {
        name = node.slug
        keys = [node.slug, Slug.normalizedText(of: node.name)]
    }

    /// Makes the candidates of some nodes, in slug order.
    ///
    /// - Parameter nodes: The states of the nodes.
    /// - Returns: The candidates.
    static func ofNodes(_ nodes: [some SlugNamedState]) -> [NameCandidate] {
        nodes.sorted { first, second in first.slug < second.slug }.map { node in NameCandidate(node: node) }
    }
}

/// A candidate, with its edit distance to the name of an atom.
private struct NearestName {
    /// The candidate.
    let candidate: NameCandidate

    /// The smallest edit distance from the slug of the name to a key of the candidate.
    let distance: Int

    /// `true` when the candidate is near enough to give in the message: the distance is at most
    /// ``FilterNameCheck/nearDistanceLimit``, and it is smaller than the length of the name, so that a short name does
    /// not match each name of the board.
    let isNear: Bool

    /// Measures a candidate against the slug of a name.
    ///
    /// - Parameters:
    ///   - candidate: The candidate.
    ///   - key: The slug of the name.
    init(candidate: NameCandidate, key: String) {
        self.candidate = candidate
        distance = candidate.keys.map { candidateKey in key.editDistance(to: candidateKey) }.min() ?? key.count
        isNear = distance <= FilterNameCheck.nearDistanceLimit && distance < key.count
    }
}
