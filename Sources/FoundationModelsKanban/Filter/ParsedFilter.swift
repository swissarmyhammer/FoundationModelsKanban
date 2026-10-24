import Foundation

/// A parsed filter, or a part of it, with the text of each atom (plan.md §6.3, divergence.md §17).
///
/// Each rule of ``FilterParser`` gives this value. The expression is the AST, and it holds no positions, so that two
/// filters with the same meaning give equal expressions. The atoms keep their text in the filter, so that the name
/// check (``FilterNameCheck``) can give the position of a name that names nothing.
struct ParsedFilter: Sendable {
    /// The expression of the filter.
    let expression: FilterExpr

    /// Each atom of the filter, in the order of the text.
    let atoms: [FilterAtomText]
}

/// One atom of a filter, with its text.
struct FilterAtomText: Sendable {
    /// The kind of the atom.
    let kind: FilterAtomKind

    /// The value of the atom.
    let value: FilterValue

    /// The text of the full atom in the filter, with its sigil, for example `#bug`. Its indices are indices of the
    /// filter.
    let text: Substring
}

extension ParsedFilter {
    /// Reads a full filter.
    ///
    /// - Parameter filter: The text of the filter, for example `#bug && @alice`.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse. The error gives the position of the problem, the problem, and one correct filter.
    init(parsing filter: String) throws(KanbanError) {
        var input = filter[...]
        do throws(FilterSyntaxError) {
            self = try FilterParser.Filter().parse(&input)
        } catch {
            throw error.kanbanError(in: filter)
        }
    }

    /// Makes the parsed filter of one atom.
    ///
    /// - Parameters:
    ///   - kind: The kind of the atom.
    ///   - value: The value of the atom.
    ///   - text: The text of the full atom in the filter.
    init(atom kind: FilterAtomKind, value: FilterValue, text: Substring) {
        expression = .atom(kind, value)
        atoms = [FilterAtomText(kind: kind, value: value, text: text)]
    }

    /// Joins this filter and the filter after it with a binary operator.
    ///
    /// - Parameters:
    ///   - other: The filter after this filter in the text.
    ///   - combine: The operator, for example ``FilterExpr/and(_:_:)``.
    /// - Returns: The joined filter, with the atoms of this filter first.
    func joined(with other: ParsedFilter, by combine: (FilterExpr, FilterExpr) -> FilterExpr) -> ParsedFilter {
        ParsedFilter(expression: combine(expression, other.expression), atoms: atoms + other.atoms)
    }

    /// Gives the NOT of this filter, with the same atoms.
    var negated: ParsedFilter {
        ParsedFilter(expression: .not(expression), atoms: atoms)
    }
}
