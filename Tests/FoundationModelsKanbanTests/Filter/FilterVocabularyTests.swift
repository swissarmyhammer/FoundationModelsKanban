import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the vocabulary of the board that the filter agent adds after its system prompt (divergence.md §17, "The
/// vocabulary of the board").
///
/// The board of the tests is the sample board of ``FilterEvaluatorTests``, with a name and a description on the tag
/// `bug`, and the column `backlog`. Each test compares the full text.
@Suite("Filter vocabulary")
struct FilterVocabularyTests {
    /// The slug of the tag that gets a name and a description.
    static let bugTag = "bug"

    /// The name of the tag `bug`.
    static let bugName = "Bug"

    /// The description of the tag `bug`: two lines, which the vocabulary writes on one line.
    static let bugDescription = "Something that does not work.\nFix it first."

    /// The slug of a column that has the order of the first column, and a slug that sorts before it.
    static let backlogColumn = "backlog"

    /// The order of the column `backlog`: the order of the first column `todo`.
    static let backlogOrder = 0

    /// The caller actor of the tests: the actor `alice` of the sample board.
    static let alice = SessionActor(
        ref: .actor(slug: FilterEvaluatorTests.alice),
        name: FilterEvaluatorTests.aliceName
    )

    /// The tags, the actors, and the columns of the board of the tests.
    static let boardVocabulary = """
        ## The vocabulary of the board

        ### Tags

        - `bug` (Bug): Something that does not work. Fix it first.
        - `defect`
        - `docs`
        - `done`
        - `feature`

        ### Actors

        - `alice` (Alice Smith)
        - `will` (Will)

        ### Columns

        The columns in board order, from the first column to the terminal column:

        1. `backlog`
        2. `todo`
        3. `doing` (In Progress)
        4. `review`
        5. `done`
        """

    /// The caller part of the vocabulary when the caller actor is `alice`.
    static let aliceCaller = """
        ### The caller

        The caller actor is `alice` (Alice Smith). For "me", "my", "I", or "my tasks", write `@alice`.
        """

    /// The caller part of the vocabulary when there is no caller actor.
    static let noCaller = """
        ### The caller

        There is no caller actor. "Me", "my", "I", and "my tasks" have no meaning: do not write an `@` atom for them.
        """

    /// Makes the board of the tests.
    ///
    /// - Returns: The sample board of ``FilterEvaluatorTests``, with a name and a description on the tag `bug`, and
    ///   the column `backlog`.
    /// - Throws: An error when a test ULID is not valid.
    static func board() throws -> ReadinessFixture {
        var board = try FilterEvaluatorTests.sampleBoard()
        board.addTag(withSlug: bugTag, named: bugName, describedAs: bugDescription)
        board.addColumn(withSlug: backlogColumn, order: backlogOrder)
        return board
    }

    /// Gives the vocabulary of a board for a caller.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - caller: The caller actor, or `nil` for no caller actor.
    /// - Returns: The text of the vocabulary.
    static func vocabulary(of board: ReadinessFixture, for caller: SessionActor?) -> String {
        FilterVocabulary.text(of: BoardView(of: board.graph, inBoard: FilterEvaluatorTests.boardKey), for: caller)
    }

    /// Gives the full vocabulary of the board of the tests with one caller part.
    ///
    /// - Parameter callerPart: The expected caller part.
    /// - Returns: The expected text.
    static func expectedText(withCaller callerPart: String) -> String {
        "\(boardVocabulary)\n\n\(callerPart)\n"
    }

    @Test("The vocabulary names each live tag, actor, and column of the board, and the caller actor with the me rule")
    func vocabularyNamesBoardAndCaller() throws {
        let expected = Self.expectedText(withCaller: Self.aliceCaller)
        #expect(Self.vocabulary(of: try Self.board(), for: Self.alice) == expected)
    }

    @Test("With no caller actor, the vocabulary tells that me has no meaning")
    func vocabularyWithNoCallerSaysMeHasNoMeaning() throws {
        #expect(Self.vocabulary(of: try Self.board(), for: nil) == Self.expectedText(withCaller: Self.noCaller))
    }

    @Test("A board with no tags and no actors gives the word none in those parts")
    func emptyPartsSayNone() {
        let expected = """
            ## The vocabulary of the board

            ### Tags

            - none

            ### Actors

            - none

            ### Columns

            The columns in board order, from the first column to the terminal column:

            1. `todo`
            2. `doing`
            3. `review`
            4. `done`

            \(Self.noCaller)

            """
        #expect(Self.vocabulary(of: ReadinessFixture(), for: nil) == expected)
    }

    @Test("Two calls on the same board give the same text")
    func twoCallsGiveSameText() throws {
        let board = try Self.board()
        let first = Self.vocabulary(of: board, for: Self.alice)
        #expect(Self.vocabulary(of: board, for: Self.alice) == first)
    }
}
