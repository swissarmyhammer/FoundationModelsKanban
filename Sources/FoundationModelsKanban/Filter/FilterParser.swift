import Foundation
import Parsing

/// The parser of the filter language (plan.md §6.3, §12 item 24).
///
/// Each grammar rule is one `Parser` type of `swift-parsing`:
///
/// ```
/// filter   = expr                                          // not empty, and no text after it
/// expr     = or_expr
/// or_expr  = and_expr (("||"|"or"|"OR") and_expr)*
/// and_expr = not_expr (("&&"|"and"|"AND")? not_expr)*      // two terms next to each other = AND
/// not_expr = ("!"|"not"|"NOT") not_expr | atom
/// atom     = ("#"|"@"|"^"|"%") body | url | "(" expr ")"
/// url      = "kanban://" body
/// body     = [^ whitespace #@^%$()&|!]+
/// ```
///
/// The rules throw ``FilterSyntaxError``, which holds the range of the problem. The `swift-parsing` error type is
/// internal to that library and has no position, so the rules never let it out. A library parser runs only in
/// `Optionally`, where a failure means "not here". `Many` and `OneOf` catch each error of their parts, so the chains of
/// `OrExpr` and `AndExpr` are loops in the rules: then an error after an operator, for example `#bug && $auth`, keeps
/// its own position.
enum FilterParser {
    /// The character that starts a group.
    static let openGroup: Character = "("

    /// The character that ends a group.
    static let closeGroup: Character = ")"

    /// The sigil of the removed `$project` atom. It is not a body character, so `$x` is a clear error.
    static let removedSigil: Character = "$"

    /// The characters that end a body: each sigil, the removed sigil, the parentheses, and each operator character.
    static let bodyStopCharacters: Set<Character> = Set(FilterAtomKind.allCases.map(\.sigil))
        .union([removedSigil, openGroup, closeGroup])
        .union(Operator.allCases.flatMap(\.symbol))

    /// Removes the whitespace at the start of the input.
    ///
    /// - Parameter input: The rest of the filter.
    static func skipWhitespace(in input: inout Substring) {
        input = input.drop(while: \.isWhitespace)
    }

    /// Tells if a filter term can start at the start of the input.
    ///
    /// - Parameter input: The rest of the filter, with no whitespace at its start.
    /// - Returns: `false` at the end of the filter, at a `)`, and at a binary operator. Else `true`.
    static func canStartTerm(at input: Substring) -> Bool {
        guard let first = input.first, first != closeGroup else {
            return false
        }
        var rest = input
        return Optionally { OneOf { Operator.and; Operator.or } }.parse(&rest) == nil
    }

    /// Makes sure that a filter term follows an operator.
    ///
    /// - Parameters:
    ///   - operatorText: The operator as the filter writes it, for example `&&` or `(`.
    ///   - input: The rest of the filter after the operator. The whitespace at its start is removed.
    /// - Throws: ``FilterSyntaxError/Problem/missingTerm(afterOperator:)`` at the operator when no term can start.
    static func requireTerm(after operatorText: Substring, in input: inout Substring) throws(FilterSyntaxError) {
        skipWhitespace(in: &input)
        guard canStartTerm(at: input) else {
            throw FilterSyntaxError(problem: .missingTerm(afterOperator: String(operatorText)), at: operatorText)
        }
    }
}

// MARK: - Rules

extension FilterParser {
    /// The full filter: one expression, with no text after it. An empty filter is an error.
    struct Filter: Parser {
        /// Reads a full filter.
        ///
        /// - Parameter input: The full filter. The parse consumes all of it.
        /// - Returns: The parsed filter.
        /// - Throws: ``FilterSyntaxError`` at the first problem.
        func parse(_ input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            let filter = input
            FilterParser.skipWhitespace(in: &input)
            guard !input.isEmpty else {
                throw FilterSyntaxError(problem: .emptyFilter, at: filter)
            }
            let expression = try OrExpr().parse(&input)
            // `OrExpr` stops only at the end of the filter or at a `)` that no group opened.
            guard input.isEmpty else {
                throw FilterSyntaxError(problem: .unmatchedClose, at: input.prefix(1))
            }
            return expression
        }
    }

    /// The rule `or_expr`: AND expressions with an OR operator between each two.
    struct OrExpr: Parser {
        /// Reads an OR chain. The chain is left-associative.
        ///
        /// - Parameter input: The rest of the filter.
        /// - Returns: The expression.
        /// - Throws: ``FilterSyntaxError`` at the first problem.
        func parse(_ input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            var expression = try AndExpr().parse(&input)
            while let operatorText = Operator.or.consume(from: &input) {
                try FilterParser.requireTerm(after: operatorText, in: &input)
                expression = .or(expression, try AndExpr().parse(&input))
            }
            return expression
        }
    }

    /// The rule `and_expr`: NOT expressions with an optional AND operator between each two.
    struct AndExpr: Parser {
        /// Reads an AND chain. Two terms next to each other are an AND. The chain is left-associative.
        ///
        /// - Parameter input: The rest of the filter.
        /// - Returns: The expression.
        /// - Throws: ``FilterSyntaxError`` at the first problem.
        func parse(_ input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            var expression = try NotExpr().parse(&input)
            while true {
                if let operatorText = Operator.and.consume(from: &input) {
                    try FilterParser.requireTerm(after: operatorText, in: &input)
                } else if !FilterParser.canStartTerm(at: input) {
                    return expression
                }
                expression = .and(expression, try NotExpr().parse(&input))
            }
        }
    }

    /// The rule `not_expr`: NOT operators before an atom.
    struct NotExpr: Parser {
        /// Reads an atom with its NOT operators.
        ///
        /// - Parameter input: The rest of the filter.
        /// - Returns: The expression.
        /// - Throws: ``FilterSyntaxError`` at the first problem.
        func parse(_ input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            guard let operatorText = Operator.not.consume(from: &input) else {
                return try Atom().parse(&input)
            }
            try FilterParser.requireTerm(after: operatorText, in: &input)
            return .not(try NotExpr().parse(&input))
        }
    }

    /// The rule `atom`: a sigil and a body, a bare `kanban://` URL, or a group.
    ///
    /// The group `"(" expr ")"` calls ``OrExpr`` again. `swift-parsing` gives `Lazy` for this recursion, but `Lazy` is
    /// deprecated, and it is a class with a mutable cache that is not `Sendable`. Thus the atom makes the inner
    /// ``OrExpr`` in its `parse` method, only when the input has a `(`. This is the same lazy evaluation, and it is the
    /// form that the library recommends.
    struct Atom: Parser {
        /// Reads one atom or one group.
        ///
        /// - Parameter input: The rest of the filter.
        /// - Returns: The atom, or the expression of the group.
        /// - Throws: ``FilterSyntaxError`` at the first problem.
        func parse(_ input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            FilterParser.skipWhitespace(in: &input)
            guard let first = input.first else {
                throw FilterSyntaxError(problem: .notATerm(text: ""), at: input)
            }
            if first == FilterParser.openGroup {
                return try Self.group(in: &input)
            }
            if first == FilterParser.removedSigil {
                throw Self.removedSigilError(in: &input)
            }
            if let kind = FilterAtomKind(sigil: first) {
                return try Self.sigilAtom(of: kind, in: &input)
            }
            return try Self.bareURLAtom(in: &input)
        }

        /// Reads a group: a `(`, an expression, and a `)`.
        ///
        /// - Parameter input: The rest of the filter, at the `(`.
        /// - Returns: The expression in the group.
        /// - Throws: ``FilterSyntaxError/Problem/unclosedGroup`` at the `(` when the group has no `)`, or the
        ///   error of the expression.
        private static func group(in input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            let open = input.prefix(1)
            input.removeFirst()
            try FilterParser.requireTerm(after: open, in: &input)
            let expression = try OrExpr().parse(&input)
            guard input.first == FilterParser.closeGroup else {
                throw FilterSyntaxError(problem: .unclosedGroup, at: open)
            }
            input.removeFirst()
            return expression
        }

        /// Reads the removed `$project` atom, to give its error.
        ///
        /// - Parameter input: The rest of the filter, at the `$`.
        /// - Returns: The error over the `$` and its body.
        private static func removedSigilError(in input: inout Substring) -> FilterSyntaxError {
            let start = input
            input.removeFirst()
            let name = Optionally { FilterParser.Body() }.parse(&input).map(String.init) ?? ""
            return FilterSyntaxError(problem: .removedSigil(name: name), at: start[..<input.startIndex])
        }

        /// Reads an atom with a sigil.
        ///
        /// - Parameters:
        ///   - kind: The kind of the sigil.
        ///   - input: The rest of the filter, at the sigil.
        /// - Returns: The atom, with a name or a URL as its value.
        /// - Throws: ``FilterSyntaxError/Problem/missingBody(kind:)`` when no body follows the sigil, or the error of
        ///   a URL body.
        private static func sigilAtom(of kind: FilterAtomKind, in input: inout Substring) throws(FilterSyntaxError)
            -> FilterExpr
        {
            let start = input
            input.removeFirst()
            guard let body = Optionally({ FilterParser.Body() }).parse(&input) else {
                throw FilterSyntaxError(problem: .missingBody(kind: kind), at: start[..<input.startIndex])
            }
            guard NodeURI.hasScheme(atStartOf: String(body)) else {
                return .atom(kind, .name(String(body)))
            }
            let atom = start[..<input.startIndex]
            let (urlKind, uri) = try urlTarget(of: body, at: atom)
            guard urlKind == kind else {
                throw FilterSyntaxError(problem: .wrongURLType(sigilKind: kind, urlKind: urlKind, uri: uri), at: atom)
            }
            return .atom(kind, .uri(uri))
        }

        /// Reads a bare `kanban://` URL. Other text cannot start a filter term.
        ///
        /// - Parameter input: The rest of the filter, at a character that is not a sigil and not a `(`.
        /// - Returns: The atom of the node type of the URL.
        /// - Throws: ``FilterSyntaxError/Problem/notATerm(text:)`` when the text is not a URL, or the error of the
        ///   URL.
        private static func bareURLAtom(in input: inout Substring) throws(FilterSyntaxError) -> FilterExpr {
            let start = input
            let body = Optionally { FilterParser.Body() }.parse(&input)
            guard let body, NodeURI.hasScheme(atStartOf: String(body)) else {
                let text = start.prefix { $0.isFilterBodyCharacter }
                let shown = text.isEmpty ? start.prefix(1) : text
                throw FilterSyntaxError(problem: .notATerm(text: String(shown)), at: shown)
            }
            let (kind, uri) = try urlTarget(of: body, at: body)
            return .atom(kind, .uri(uri))
        }

        /// Reads the URL of a URL atom, and finds the kind of atom of its node type.
        ///
        /// - Parameters:
        ///   - body: The body that starts with `kanban://`.
        ///   - atom: The text of the full atom, for the position of an error.
        /// - Returns: The kind of atom that accepts the URL, and the URL.
        /// - Throws: ``FilterSyntaxError/Problem/invalidURL(url:)`` when the body is not a node URL.
        ///   ``FilterSyntaxError/Problem/unusableURL(uri:)`` when no atom accepts the node type of the URL.
        private static func urlTarget(of body: Substring, at atom: Substring) throws(FilterSyntaxError)
            -> (FilterAtomKind, NodeURI)
        {
            guard let uri = try? NodeURI(parsing: String(body)) else {
                throw FilterSyntaxError(problem: .invalidURL(url: String(body)), at: atom)
            }
            guard let kind = FilterAtomKind(nodeType: uri.ref.nodeType) else {
                throw FilterSyntaxError(problem: .unusableURL(uri: uri), at: atom)
            }
            return (kind, uri)
        }
    }

    /// The rule `body`: one or more characters that are not whitespace and not in ``bodyStopCharacters``.
    ///
    /// The body accepts `:` and `/`, so a `kanban://` URL is a body.
    struct Body: Parser {
        /// The parser of the body.
        var body: some Parser<Substring, Substring> {
            Prefix(1...) { $0.isFilterBodyCharacter }
        }
    }
}

// MARK: - Operators

extension FilterParser {
    /// An operator of the filter language: a symbol, or a keyword in lowercase or in uppercase.
    ///
    /// As a parser, an operator reads its symbol or its keyword and gives the text that it read. A keyword needs a word
    /// boundary after it, so `nothing` is not `not` and `android` is not `and`.
    enum Operator: CaseIterable, Parser {
        /// `&&`, `and`, or `AND`.
        case and

        /// `||`, `or`, or `OR`.
        case or

        /// `!`, `not`, or `NOT`.
        case not

        /// The symbol of the operator, for example `&&`.
        var symbol: String {
            spelling.symbol
        }

        /// The keyword of the operator in lowercase, for example `and`.
        var word: String {
            spelling.word
        }

        /// The symbol and the keyword of the operator.
        private var spelling: (symbol: String, word: String) {
            switch self {
            case .and: ("&&", "and")
            case .or: ("||", "or")
            case .not: ("!", "not")
            }
        }

        /// The parser of the operator. It gives the text that it read.
        var body: some Parser<Substring, Substring> {
            Consumed {
                OneOf {
                    symbol
                    Keyword(word: word)
                    Keyword(word: word.uppercased())
                }
            }
        }

        /// Reads the operator, after whitespace, when the input starts with it.
        ///
        /// - Parameter input: The rest of the filter. The whitespace at its start is removed in all cases.
        /// - Returns: The text of the operator, or `nil` when the input does not start with the operator. Then the
        ///   input does not change after its whitespace.
        func consume(from input: inout Substring) -> Substring? {
            FilterParser.skipWhitespace(in: &input)
            return Optionally { self }.parse(&input)
        }
    }

    /// A keyword with a word boundary after it: the next character is not a letter, a digit, or `_`.
    struct Keyword: Parser {
        /// The text of the keyword.
        let word: String

        /// The parser of the keyword. It does not consume the character after the keyword.
        var body: some Parser<Substring, Void> {
            word
            Not { Prefix(1) { $0.isFilterWordCharacter } }
        }
    }
}

// MARK: - Character classes

extension Character {
    /// Tells if the character can be in the body of a filter atom: it is not whitespace and not in
    /// ``FilterParser/bodyStopCharacters``.
    var isFilterBodyCharacter: Bool {
        !isWhitespace && !FilterParser.bodyStopCharacters.contains(self)
    }

    /// Tells if the character continues a word, so that a keyword before it is not a keyword: a letter, a digit, or
    /// `_`.
    var isFilterWordCharacter: Bool {
        isLetter || isNumber || self == "_"
    }
}
