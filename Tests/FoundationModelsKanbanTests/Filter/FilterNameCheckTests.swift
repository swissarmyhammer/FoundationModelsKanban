import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the name check of the filter agent (divergence.md §17, "The loop"): a filter passes only when it parses and
/// each tag, actor, and column name in it names a node of the board.
///
/// The board is the sample board of ``FilterEvaluatorTests``: the tags `bug`, `feature`, `docs`, `done`, `defect`,
/// and `old` (renamed to `defect`), the actors `alice` (`Alice Smith`) and `will`, and the columns `todo`, `doing`
/// (`In Progress`), `review`, and `done`.
@Suite("Filter name check")
struct FilterNameCheckTests {
    /// The slug of an actor of a different board that a task of the board has as its assignee.
    static let remoteActor = "bob"

    /// Checks the names of a filter against a board.
    ///
    /// - Parameters:
    ///   - filter: The text of the filter.
    ///   - board: The board.
    /// - Returns: The parsed filter.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter does not parse or a
    ///   name names nothing.
    static func check(_ filter: String, in board: ReadinessFixture) throws(KanbanError) -> FilterExpr {
        try FilterNameCheck(over: board.readiness, inBoard: FilterEvaluatorTests.boardKey).check(filter)
    }

    /// Checks the names of a filter against the sample board.
    ///
    /// - Parameter filter: The text of the filter.
    /// - Returns: The parsed filter.
    /// - Throws: The error of the check, or an error when a test ULID is not valid.
    static func sampleCheck(_ filter: String) throws -> FilterExpr {
        try check(filter, in: try FilterEvaluatorTests.sampleBoard())
    }

    /// Gives the error of a name that names nothing.
    ///
    /// - Parameters:
    ///   - filter: The text of the filter.
    ///   - atom: The text of the atom with the name. The position of the error is the first occurrence of it.
    ///   - detail: The detail of the error.
    ///   - example: The corrected filter.
    /// - Returns: The `INVALID_FILTER` error.
    /// - Throws: An error of `#require` when the filter does not hold the atom.
    static func unknownName(
        in filter: String,
        at atom: String,
        detail: String,
        example: String
    ) throws -> KanbanError {
        .invalidFilter(
            filter: filter,
            position: try FilterParserTests.position(of: atom, in: filter),
            detail: detail,
            example: example
        )
    }

    // MARK: - Known names

    @Test("A filter with only known names gives the parsed filter")
    func knownNamesPass() throws {
        let expected = FilterExpr.and(
            .and(.atom(.tag, .name("bug")), .atom(.assignee, .name("alice"))),
            .not(.atom(.column, .name("doing")))
        )
        #expect(try Self.sampleCheck("#bug @alice !%doing") == expected)
    }

    /// Each form of a known name: a slug in a different case, the slug of a name, a renamed tag, a URL of the board,
    /// a URL of a different board, and the atoms `^` and `~`, which the check does not read.
    static let knownForms = [
        "#BUG",
        "#old",
        "@alice-smith",
        "@WILL",
        "%in-progress",
        "%review",
        FilterEvaluatorTests.url(ofType: .tag, withID: "feature"),
        "%" + FilterEvaluatorTests.url(ofType: .column, withID: "x", inBoard: FilterEvaluatorTests.otherBoardKey),
        "^\(FilterEvaluatorTests.ghost)",
        "~comment",
    ]

    @Test("Each form of a known name passes", arguments: knownForms)
    func knownFormPasses(_ filter: String) throws {
        #expect(try Self.sampleCheck(filter) == FilterExpr(parsing: filter))
    }

    @Test("Each virtual tag passes, also in lowercase", arguments: VirtualTag.allCases)
    func virtualTagPasses(_ tag: VirtualTag) throws {
        let filter = "#\(tag.rawValue) || #\(tag.rawValue.lowercased())"
        #expect(try Self.sampleCheck(filter) == FilterExpr(parsing: filter))
    }

    @Test("An actor of a different board that a task has as its assignee passes")
    func remoteAssigneePasses() throws {
        var board = try FilterEvaluatorTests.sampleBoard()
        let actorURL = FilterEvaluatorTests.url(
            ofType: .actor,
            withID: Self.remoteActor,
            inBoard: FilterEvaluatorTests.otherBoardKey
        )
        try board.addTask(withULID: FilterEvaluatorTests.ghost, assignedToRemote: [try NodeURI(parsing: actorURL)])
        #expect(try Self.check("@\(Self.remoteActor)", in: board) == .atom(.assignee, .name(Self.remoteActor)))
    }

    // MARK: - Unknown names

    @Test("An unknown tag gives INVALID_FILTER at the tag, with the nearest tag in the message")
    func unknownTagGivesNearestTag() throws {
        let filter = "#bug && #featur"
        let expected = try Self.unknownName(
            in: filter,
            at: "#featur",
            detail: "no tag named `featur`; the nearest tag is `feature`",
            example: "#bug && #feature"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("A tag name near a virtual tag gives the virtual tag as the nearest tag")
    func nearVirtualTagGivesVirtualTag() throws {
        let filter = "#REDY"
        let expected = try Self.unknownName(
            in: filter,
            at: filter,
            detail: "no tag named `REDY`; the nearest tag is `READY`",
            example: "#READY"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("An unknown column gives INVALID_FILTER at the column, with the nearest column in the message")
    func unknownColumnGivesNearestColumn() throws {
        let filter = "@will (%doign || #bug)"
        let expected = try Self.unknownName(
            in: filter,
            at: "%doign",
            detail: "no column named `doign`; the nearest column is `doing`",
            example: "@will (%doing || #bug)"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("An unknown actor with no near actor gives no nearest actor, and the example uses the nearest actor")
    func unknownActorWithNoNearActor() throws {
        let filter = "!@zed"
        let expected = try Self.unknownName(in: filter, at: "@zed", detail: "no actor named `zed`", example: "!@will")
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("An unknown actor on a board with no actor gives the example of the atom kind")
    func unknownActorOnBoardWithNoActor() throws {
        let filter = "@bob"
        let expected = try Self.unknownName(
            in: filter,
            at: filter,
            detail: "no actor named `bob`",
            example: FilterAtomKind.assignee.example
        )
        #expect(throws: expected) {
            try Self.check(filter, in: ReadinessFixture())
        }
    }

    @Test("A tag URL of the board with an unknown slug gives INVALID_FILTER at the full URL")
    func unknownTagURL() throws {
        let filter = FilterEvaluatorTests.url(ofType: .tag, withID: "featur")
        let expected = try Self.unknownName(
            in: filter,
            at: filter,
            detail: "no tag named `featur`; the nearest tag is `feature`",
            example: "#feature"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("The first unknown name in the filter gives the error")
    func firstUnknownNameGivesError() throws {
        let filter = "%nowhere @zed"
        let expected = try Self.unknownName(
            in: filter,
            at: "%nowhere",
            detail: "no column named `nowhere`",
            example: "%done @zed"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }

    @Test("A project atom gives the INVALID_FILTER of the parser, because the board has no projects")
    func projectGivesParseError() throws {
        let filter = "#bug $auth"
        let expected = try Self.unknownName(
            in: filter,
            at: "$auth",
            detail: "`$` is removed; use `#auth` for a tag or `%auth` for a column",
            example: "#auth"
        )
        #expect(throws: expected) {
            try Self.sampleCheck(filter)
        }
    }
}
