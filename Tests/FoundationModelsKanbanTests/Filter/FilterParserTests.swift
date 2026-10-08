import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the parse of the filter language to an AST (plan.md §6.3, §12 items 22 and 24).
///
/// The atom, operator, precedence, grouping, whitespace, and error cases are a port of the parser tests in the Rust
/// files `swissarmyhammer-filter-expr/src/lib.rs` and `src/parser.rs`. The `$project` atom is removed, so each Rust
/// `$project` test now expects `INVALID_FILTER`. The URL forms, the keyword word boundary, and the error messages and
/// positions are new.
@Suite("Filter parser")
struct FilterParserTests {
    /// The board key of the URL tests.
    static let boardKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The ULID text of the task in the URL tests.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The URL of a task.
    static let taskURL = "kanban://\(boardKey)/task/\(taskULID)"

    /// The URL of the tag `bug`.
    static let tagURL = "kanban://\(boardKey)/tag/bug"

    /// The URL of the actor `alice`.
    static let actorURL = "kanban://\(boardKey)/actor/alice"

    /// The URL of the column `doing`.
    static let columnURL = "kanban://\(boardKey)/column/doing"

    /// The URL of the board.
    static let boardURL = "kanban://\(boardKey)/board"

    /// The URL of a comment.
    static let commentURL = "kanban://\(boardKey)/comment/\(taskULID)"

    /// The example of each error of an operator with no term after it.
    static let operatorExample = "#bug && @alice"

    /// The example of each error of a group.
    static let groupExample = "(#bug || #feature) && @alice"

    // MARK: - Atoms

    @Test("A tag atom")
    func tagAtom() throws {
        #expect(try FilterExpr(parsing: "#bug") == .atom(.tag, .name("bug")))
    }

    @Test("An assignee atom")
    func assigneeAtom() throws {
        #expect(try FilterExpr(parsing: "@alice") == .atom(.assignee, .name("alice")))
    }

    @Test("A ref atom")
    func refAtom() throws {
        #expect(try FilterExpr(parsing: "^01ABC") == .atom(.ref, .name("01ABC")))
    }

    @Test("A column atom")
    func columnAtom() throws {
        #expect(try FilterExpr(parsing: "%doing") == .atom(.column, .name("doing")))
    }

    @Test("A node type atom")
    func nodeTypeAtom() throws {
        #expect(try FilterExpr(parsing: "~task") == .atom(.type, .name("task")))
    }

    @Test("A ~ ends the body of the atom before it, so two atoms with no space make an AND")
    func nodeTypeSigilEndsBody() throws {
        #expect(try FilterExpr(parsing: "#bug~task") == .and(.atom(.tag, .name("bug")), .atom(.type, .name("task"))))
    }

    @Test("A tag name keeps hyphens, dots, and underscores", arguments: ["bug-fix", "v2.0", "my_tag"])
    func tagKeepsPunctuation(name: String) throws {
        #expect(try FilterExpr(parsing: "#\(name)") == .atom(.tag, .name(name)))
    }

    @Test("Tags with hyphens and dots combine with AND")
    func tagsWithHyphensAndDots() throws {
        let expected = FilterExpr.and(.atom(.tag, .name("v2.0")), .atom(.tag, .name("bug-fix")))
        #expect(try FilterExpr(parsing: "#v2.0 && #bug-fix") == expected)
    }

    // MARK: - NOT

    @Test("NOT with each of its forms", arguments: ["!#done", "not #done", "NOT #done"])
    func notForms(filter: String) throws {
        #expect(try FilterExpr(parsing: filter) == .not(.atom(.tag, .name("done"))))
    }

    @Test("Two NOT operators nest")
    func doubleNot() throws {
        #expect(try FilterExpr(parsing: "!!#done") == .not(.not(.atom(.tag, .name("done")))))
    }

    @Test("The keyword not before a group needs no space")
    func notBeforeGroup() throws {
        #expect(try FilterExpr(parsing: "not(#done)") == .not(.atom(.tag, .name("done"))))
    }

    @Test("A word that starts with not is not the keyword not")
    func nothingIsNotNot() throws {
        let filter = "nothing"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: 0..<filter.count,
            detail: Self.notATermDetail(for: filter),
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    // MARK: - AND

    @Test("AND with each of its forms", arguments: ["#a && #b", "#a and #b", "#a AND #b", "#a #b", "#a  &&  #b"])
    func andForms(filter: String) throws {
        #expect(try FilterExpr(parsing: filter) == .and(.atom(.tag, .name("a")), .atom(.tag, .name("b"))))
    }

    @Test("A tag and an assignee, with explicit and implicit AND", arguments: ["#bug && @will", "#bug @will"])
    func tagAndAssignee(filter: String) throws {
        #expect(try FilterExpr(parsing: filter) == .and(.atom(.tag, .name("bug")), .atom(.assignee, .name("will"))))
    }

    @Test("Three atoms next to each other make a left-associative AND chain")
    func implicitAndOfThree() throws {
        let expected = FilterExpr.and(.and(.atom(.tag, .name("a")), .atom(.tag, .name("b"))), .atom(.tag, .name("c")))
        #expect(try FilterExpr(parsing: "#a #b #c") == expected)
    }

    @Test("A keyword operator needs no space before a sigil")
    func keywordBeforeSigil() throws {
        #expect(try FilterExpr(parsing: "#a or#b") == .or(.atom(.tag, .name("a")), .atom(.tag, .name("b"))))
    }

    // MARK: - OR

    @Test("OR with each of its forms", arguments: ["#a || #b", "#a or #b", "#a OR #b"])
    func orForms(filter: String) throws {
        #expect(try FilterExpr(parsing: filter) == .or(.atom(.tag, .name("a")), .atom(.tag, .name("b"))))
    }

    @Test("Two tags with OR")
    func orOfTwoTags() throws {
        let expected = FilterExpr.or(.atom(.tag, .name("bug")), .atom(.tag, .name("feature")))
        #expect(try FilterExpr(parsing: "#bug || #feature") == expected)
    }

    // MARK: - Precedence and grouping

    @Test("AND binds tighter than OR")
    func andBindsTighterThanOr() throws {
        let expected = FilterExpr.or(.atom(.tag, .name("a")), .and(.atom(.tag, .name("b")), .atom(.tag, .name("c"))))
        #expect(try FilterExpr(parsing: "#a || #b && #c") == expected)
    }

    @Test("NOT binds tighter than AND")
    func notBindsTighterThanAnd() throws {
        #expect(try FilterExpr(parsing: "!#a && #b") == .and(.not(.atom(.tag, .name("a"))), .atom(.tag, .name("b"))))
    }

    @Test("A group overrides the precedence")
    func groupOverridesPrecedence() throws {
        let expected = FilterExpr.and(.or(.atom(.tag, .name("a")), .atom(.tag, .name("b"))), .atom(.tag, .name("c")))
        #expect(try FilterExpr(parsing: "(#a || #b) && #c") == expected)
    }

    @Test("Nested groups give the inner expression")
    func nestedGroups() throws {
        #expect(try FilterExpr(parsing: "((#a))") == .atom(.tag, .name("a")))
    }

    @Test("Keyword operators of each case form give the same tree", arguments: [
        "not #done and @will or #bug", "NOT #done AND @will OR #bug",
    ])
    func keywordOperatorsFull(filter: String) throws {
        let notDone = FilterExpr.not(.atom(.tag, .name("done")))
        let expected = FilterExpr.or(.and(notDone, .atom(.assignee, .name("will"))), .atom(.tag, .name("bug")))
        #expect(try FilterExpr(parsing: filter) == expected)
    }

    // MARK: - Whitespace

    @Test("Leading and trailing whitespace is ignored")
    func outerWhitespace() throws {
        #expect(try FilterExpr(parsing: "  #bug  ") == .atom(.tag, .name("bug")))
    }

    // MARK: - URL atoms

    @Test("A URL after a sigil gives the atom of the sigil", arguments: [
        ("^", taskURL, FilterAtomKind.ref), ("#", tagURL, .tag), ("@", actorURL, .assignee), ("%", columnURL, .column),
        ("^", columnURL, .ref), ("^", tagURL, .ref), ("^", actorURL, .ref), ("^", boardURL, .ref),
        ("^", commentURL, .ref),
    ])
    func urlAfterSigil(sigil: String, url: String, kind: FilterAtomKind) throws {
        #expect(try FilterExpr(parsing: "\(sigil)\(url)") == .atom(kind, .uri(try NodeURI(parsing: url))))
    }

    @Test("A bare URL gives the atom of its node type", arguments: [
        (taskURL, FilterAtomKind.ref), (tagURL, .tag), (actorURL, .assignee), (columnURL, .column),
    ])
    func bareURL(url: String, kind: FilterAtomKind) throws {
        #expect(try FilterExpr(parsing: url) == .atom(kind, .uri(try NodeURI(parsing: url))))
    }

    @Test("The scheme of a bare URL ignores case")
    func bareURLSchemeIgnoresCase() throws {
        let upper = "KANBAN://\(Self.boardKey)/tag/bug"
        #expect(try FilterExpr(parsing: upper) == .atom(.tag, .uri(try NodeURI(parsing: Self.tagURL))))
    }

    @Test("A bare URL combines with other atoms")
    func bareURLCombines() throws {
        let tag = FilterExpr.atom(.tag, .uri(try NodeURI(parsing: Self.tagURL)))
        #expect(try FilterExpr(parsing: "\(Self.tagURL) && @alice") == .and(tag, .atom(.assignee, .name("alice"))))
    }

    @Test("A URL of the wrong type for its sigil gives the correct form")
    func urlOfWrongType() throws {
        let filter = "#\(Self.taskURL)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: 0..<filter.count,
            detail: "`#` needs a `tag` URL, but this URL is a `task` URL; use `^` for a `task` URL",
            example: "^\(Self.taskURL)"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A bare board or comment URL is not a filter term, and the error gives the ^ atom", arguments: [
        ("board", boardURL), ("comment", commentURL),
    ])
    func bareURLOfNoAtom(type: String, url: String) throws {
        #expect(throws: KanbanError.invalidFilter(
            filter: url,
            position: 0..<url.count,
            detail: "a `\(type)` URL needs `^` before it",
            example: "^\(url)"
        )) {
            try FilterExpr(parsing: url)
        }
    }

    @Test("A comment URL after # is not a filter term, and the error gives the ^ atom")
    func commentURLAfterTagSigil() throws {
        let filter = "#\(Self.commentURL)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: 0..<filter.count,
            detail: "a `comment` URL needs `^` before it",
            example: "^\(Self.commentURL)"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A URL after ~ gives the correct form, because ~ needs a node type name")
    func urlAfterNodeTypeSigil() throws {
        let filter = "~\(Self.columnURL)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: 0..<filter.count,
            detail: "`~` needs a node type name, but this URL is a `column` URL; use `%` for a `column` URL",
            example: "%\(Self.columnURL)"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A URL that does not parse gives the form of a URL")
    func malformedURL() throws {
        let filter = "#bug && #kanban://tag"
        let url = "kanban://tag"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: "#\(url)", in: filter),
            detail: "`\(url)` is not a valid node URL; a URL has the form `kanban://<board-key>/<type>/<id>`",
            example: "kanban://<board-key>/tag/bug"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    // MARK: - The removed $project atom

    @Test("Each Rust $project filter now gives INVALID_FILTER", arguments: [
        "$auth-migration", "$v2.0", "$my_project", "$", "$$bar", "$$garbage", "$$", "$auth && #bug",
        "$auth #bug @alice", "!$auth",
    ])
    func projectAtomIsInvalid(filter: String) {
        let error = #expect(throws: KanbanError.self) {
            try FilterExpr(parsing: filter)
        }
        #expect(error?.code == "INVALID_FILTER")
    }

    @Test("A $ atom tells the agent to use a tag or a column")
    func dollarAtomGivesCorrection() throws {
        #expect(throws: KanbanError.invalidFilter(
            filter: "$auth",
            position: 0..<"$auth".count,
            detail: "`$` is removed; use `#auth` for a tag or `%auth` for a column",
            example: "#auth"
        )) {
            try FilterExpr(parsing: "$auth")
        }
    }

    @Test("A $ atom after an operator gives its own position")
    func dollarAtomAfterOperator() throws {
        let filter = "#bug && $auth"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: "$auth", in: filter),
            detail: "`$` is removed; use `#auth` for a tag or `%auth` for a column",
            example: "#auth"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A $ with no name gives the position of the $ and a general correction")
    func dollarWithoutName() throws {
        #expect(throws: KanbanError.invalidFilter(
            filter: "$$",
            position: 0..<1,
            detail: "`$` is removed; use `#<name>` for a tag or `%<name>` for a column",
            example: "#bug"
        )) {
            try FilterExpr(parsing: "$$")
        }
    }

    @Test("The message of a parse error gives the start..end position")
    func messageGivesPosition() {
        let error = #expect(throws: KanbanError.self) {
            try FilterExpr(parsing: "$$")
        }
        #expect(error?.message.contains("is not valid at 0..1: ") == true)
    }

    // MARK: - Other errors

    @Test("An empty or blank filter gives INVALID_FILTER over the full filter", arguments: ["", "   "])
    func emptyFilter(filter: String) throws {
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: 0..<filter.count,
            detail: "the filter is empty",
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("An operator at the end needs a term after it", arguments: ["&&", "||", "and", "or", "!", "not"])
    func operatorAtEnd(operatorText: String) throws {
        let filter = "#bug \(operatorText)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: operatorText, in: filter),
            detail: "`\(operatorText)` needs a filter term after it",
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("Two operators in a row need a term between them")
    func twoOperators() throws {
        let filter = "#a && || #b"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: "&&", in: filter),
            detail: "`&&` needs a filter term after it",
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("An empty group needs a term")
    func emptyGroup() throws {
        #expect(throws: KanbanError.invalidFilter(
            filter: "()",
            position: 0..<1,
            detail: "`(` needs a filter term after it",
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: "()")
        }
    }

    @Test("A sigil with no body needs a name", arguments: [
        ("#", "a tag name", "#bug"), ("@", "an actor name", "@alice"), ("^", "a node id", "^ajv8v4t"),
        ("%", "a column name", "%doing"), ("~", "a node type name", "~task"),
    ])
    func sigilWithoutBody(sigil: String, noun: String, example: String) throws {
        let filter = "#bug && \(sigil)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: sigil, in: filter, fromEnd: true),
            detail: "`\(sigil)` needs \(noun)",
            example: example
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A group with no closing parenthesis gives the position of the open parenthesis")
    func unclosedGroup() throws {
        let filter = "#a && (#bug"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: "(", in: filter),
            detail: "the `(` has no matching `)`",
            example: Self.groupExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A closing parenthesis with no open parenthesis")
    func unmatchedClose() throws {
        let filter = "#bug)"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: ")", in: filter),
            detail: "the `)` has no matching `(`",
            example: Self.groupExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("Text with no sigil is not a filter term", arguments: ["#a bug", "#a & #b", "#a | #b"])
    func textWithoutSigil(filter: String) throws {
        let text = String(filter.dropFirst("#a ".count).prefix { !$0.isWhitespace })
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: text, in: filter),
            detail: Self.notATermDetail(for: text),
            example: Self.operatorExample
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("A group reports the error inside it")
    func errorInsideGroup() throws {
        let filter = "(#a || $b) && #c"
        #expect(throws: KanbanError.invalidFilter(
            filter: filter,
            position: try Self.position(of: "$b", in: filter),
            detail: "`$` is removed; use `#b` for a tag or `%b` for a column",
            example: "#b"
        )) {
            try FilterExpr(parsing: filter)
        }
    }

    @Test("The atom rule at the end of the input tells that the filter ends too early")
    func atomAtEndOfInput() {
        var input: Substring = ""
        let error = #expect(throws: FilterSyntaxError.self) {
            try FilterParser.Atom().parse(&input)
        }
        #expect(error?.problem == .notATerm(text: ""))
        #expect(error?.detail == "the filter ends where a filter term must be")
    }

    // MARK: - Helpers

    /// Finds the character range of a token in a filter.
    ///
    /// - Parameters:
    ///   - token: The token to find.
    ///   - filter: The filter that holds the token.
    ///   - isFromEnd: `true` to find the last occurrence, `false` to find the first.
    /// - Returns: The range of the token, in characters from the start of the filter.
    /// - Throws: An error of `#require` when the filter does not hold the token.
    static func position(of token: String, in filter: String, fromEnd isFromEnd: Bool = false) throws -> Range<Int> {
        let range = try #require(filter.range(of: token, options: isFromEnd ? .backwards : []))
        let start = filter.distance(from: filter.startIndex, to: range.lowerBound)
        return start..<(start + token.count)
    }

    /// Gives the detail of the error for text that cannot start a filter term.
    ///
    /// - Parameter text: The text at the position of the error.
    /// - Returns: The detail text.
    static func notATermDetail(for text: String) -> String {
        "`\(text)` cannot start a filter term; "
            + "a term starts with `#`, `@`, `^`, `%`, `~`, `(`, `!`, `not`, or `kanban://`"
    }
}
