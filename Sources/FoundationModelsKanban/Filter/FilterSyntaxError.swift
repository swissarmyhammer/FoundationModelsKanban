import Foundation

/// A failure of the filter parser at one range of the filter (plan.md §6.3).
///
/// The parser rules throw this error, and not the error of `swift-parsing`, so that the error holds the range of the
/// problem. ``kanbanError(in:)`` changes it to `INVALID_FILTER` with the tool's own message: the position as
/// `start..end` in characters, the detail, and one correct filter.
struct FilterSyntaxError: Error, Hashable, Sendable {
    /// The problem that the parser found.
    enum Problem: Hashable, Sendable {
        /// The filter is empty or has only whitespace.
        case emptyFilter

        /// The removed `$project` atom. The name is the body after the `$`, and it can be empty.
        case removedSigil(name: String)

        /// A sigil with no body after it.
        case missingBody(kind: FilterAtomKind)

        /// An operator or a `(` with no filter term after it. The text is the operator as the filter writes it.
        case missingTerm(afterOperator: String)

        /// A `(` with no `)` after its group.
        case unclosedGroup

        /// A `)` with no `(` before it.
        case unmatchedClose

        /// Text that cannot start a filter term. The text is empty at the end of the filter.
        case notATerm(text: String)

        /// A body that starts with `kanban://` but is not a valid node URL.
        case invalidURL(url: String)

        /// A URL after a sigil of a different kind. The URL kind is the kind of atom that accepts the URL.
        case wrongURLType(sigilKind: FilterAtomKind, urlKind: FilterAtomKind, uri: NodeURI)

        /// A URL of a node type that no atom accepts: the board or a comment.
        case unusableURL(uri: NodeURI)
    }

    /// The example of each problem that has no example of its own.
    static let generalExample = "#bug && @alice"

    /// The example of a problem with a group.
    static let groupExample = "(#bug || #feature) && @alice"

    /// The general form of a node URL.
    static let urlForm = "\(NodeURI.scheme)<board-key>/<type>/<id>"

    /// The example of a URL that does not parse.
    static let urlExample = "\(NodeURI.scheme)<board-key>/tag/bug"

    /// The word before the last item of a list of choices.
    static let lastChoiceWord = "or"

    /// The name in the correction of a `$` with no name.
    static let placeholderName = "<name>"

    /// The problem that the parser found.
    let problem: Problem

    /// The range of the filter where the problem is.
    let range: Range<String.Index>

    /// Makes an error at the text of the problem.
    ///
    /// - Parameters:
    ///   - problem: The problem that the parser found.
    ///   - text: The part of the filter where the problem is. It can be empty, for example at the end of the filter.
    init(problem: Problem, at text: Substring) {
        self.problem = problem
        range = text.startIndex..<text.endIndex
    }

    /// The text that tells the problem, for example ``"`&&` needs a filter term after it"``.
    var detail: String {
        explanation.detail
    }

    /// One correct filter that the agent can use in place of the filter, for example `#bug && @alice`.
    var example: String {
        explanation.example
    }

    /// Changes the error to `INVALID_FILTER` with the tool's own message.
    ///
    /// - Parameter filter: The full filter. The range of the error is in this filter.
    /// - Returns: The error, with the range as character offsets from the start of the filter.
    func kanbanError(in filter: String) -> KanbanError {
        let start = filter.distance(from: filter.startIndex, to: range.lowerBound)
        let end = filter.distance(from: filter.startIndex, to: range.upperBound)
        return .invalidFilter(filter: filter, position: start..<end, detail: detail, example: example)
    }
}

// MARK: - Explanation

extension FilterSyntaxError {
    /// The text at the start of each kind of filter term, in the order of the message, for example `#` and `(`.
    private static var termStarts: [String] {
        let notOperator = FilterParser.Operator.not
        return FilterAtomKind.allCases.map { String($0.sigil) }
            + [String(FilterParser.openGroup), notOperator.symbol, notOperator.word, NodeURI.scheme]
    }

    /// The detail and the example of the problem.
    private var explanation: (detail: String, example: String) {
        switch problem {
        case .emptyFilter:
            ("the filter is empty", Self.generalExample)
        case .removedSigil(let name):
            Self.removedSigilExplanation(forName: name)
        case .missingBody(let kind):
            ("`\(kind.sigil)` needs \(kind.bodyNoun)", kind.example)
        case .missingTerm(let operatorText):
            ("`\(operatorText)` needs a filter term after it", Self.generalExample)
        case .unclosedGroup:
            ("the `\(FilterParser.openGroup)` has no matching `\(FilterParser.closeGroup)`", Self.groupExample)
        case .unmatchedClose:
            ("the `\(FilterParser.closeGroup)` has no matching `\(FilterParser.openGroup)`", Self.groupExample)
        case .notATerm(let text):
            (Self.notATermDetail(for: text), Self.generalExample)
        case .invalidURL(let url):
            ("`\(url)` is not a valid node URL; a URL has the form `\(Self.urlForm)`", Self.urlExample)
        case .wrongURLType(let sigilKind, let urlKind, let uri):
            Self.wrongURLTypeExplanation(of: uri, after: sigilKind, acceptedBy: urlKind)
        case .unusableURL(let uri):
            Self.unusableURLExplanation(of: uri)
        }
    }

    /// Explains the removed `$project` atom.
    ///
    /// - Parameter name: The body after the `$`. It can be empty.
    /// - Returns: The detail, and the tag atom of the name as the example.
    private static func removedSigilExplanation(forName name: String) -> (detail: String, example: String) {
        let shownName = name.isEmpty ? placeholderName : name
        let tag = FilterAtomKind.tag
        let column = FilterAtomKind.column
        let detail = "`\(FilterParser.removedSigil)` is removed; use `\(tag.sigil)\(shownName)` for a tag "
            + "or `\(column.sigil)\(shownName)` for a column"
        return (detail, name.isEmpty ? tag.example : "\(tag.sigil)\(name)")
    }

    /// Tells that text cannot start a filter term.
    ///
    /// - Parameter text: The text at the position of the problem. It is empty at the end of the filter.
    /// - Returns: The detail.
    private static func notATermDetail(for text: String) -> String {
        guard !text.isEmpty else {
            return "the filter ends where a filter term must be"
        }
        let starts = choiceList(of: termStarts.map { "`\($0)`" })
        return "`\(text)` cannot start a filter term; a term starts with \(starts)"
    }

    /// Joins choices into one list, with ``lastChoiceWord`` before the last choice, for example `a, b, or c`.
    ///
    /// - Parameter choices: The choices, in the order of the list.
    /// - Returns: The list text. One choice gives the choice only, and no choice gives an empty text.
    private static func choiceList(of choices: [String]) -> String {
        guard choices.count > 1, let last = choices.last else {
            return choices.joined()
        }
        let separator = KanbanError.listSeparator
        return choices.dropLast().joined(separator: separator) + "\(separator)\(lastChoiceWord) \(last)"
    }

    /// Explains a URL after a sigil of a different kind.
    ///
    /// - Parameters:
    ///   - uri: The URL.
    ///   - sigilKind: The kind of the sigil before the URL.
    ///   - urlKind: The kind of atom that accepts the URL.
    /// - Returns: The detail, and the atom with the correct sigil as the example.
    private static func wrongURLTypeExplanation(
        of uri: NodeURI,
        after sigilKind: FilterAtomKind,
        acceptedBy urlKind: FilterAtomKind
    ) -> (detail: String, example: String) {
        let needed = sigilKind.nodeType.pathSegment
        let found = urlKind.nodeType.pathSegment
        let detail = "`\(sigilKind.sigil)` needs a `\(needed)` URL, but this URL is a `\(found)` URL; "
            + "use `\(urlKind.sigil)` for a `\(found)` URL"
        return (detail, "\(urlKind.sigil)\(uri)")
    }

    /// Explains a URL of a node type that no atom accepts.
    ///
    /// - Parameter uri: The URL.
    /// - Returns: The detail, and a tag URL of the same board as the example.
    private static func unusableURLExplanation(of uri: NodeURI) -> (detail: String, example: String) {
        let accepted = choiceList(of: FilterAtomKind.allCases.map(\.nodeType.pathSegment))
        let detail = "a \(uri.ref.nodeType.pathSegment) URL is not a filter term; use a \(accepted) URL"
        let example = NodeURI(boardKey: uri.boardKey, ref: .tag(slug: "bug"))
        return (detail, example.description)
    }
}
