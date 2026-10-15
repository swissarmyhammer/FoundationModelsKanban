import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that `column`, `tags`, `assignees`, and the comment `actor` (the author) stay in one board (divergence.md
/// R15): a full URI of a node of a different board names no node of this board. The call fails with the not-found
/// error of the node type, the same as for `column`, and writes nothing. Only `dependsOn` takes a URI of a different
/// board.
///
/// Each test writes the fixture logs of ``KanbanGraphTests`` to a temporary repo. No test reads or changes the
/// `.kanban/` directory of this repo.
@Suite("Refs to a node of a different board in one-board fields", .watcherBudget)
struct OtherBoardRefTests {
    /// The slug of the tag that the URIs name.
    static let tagSlug = "bug"

    /// The slug of the actor that the URIs name.
    static let actorSlug = "alice"

    /// One `addTask` input field that takes a node of the current board only, with the URI of a node of a different
    /// board, and the error of the call.
    struct InputCase: Sendable, CustomTestStringConvertible {
        /// The name of the field of the `input` object.
        let field: String

        /// The local ref of the node that the URI names.
        let ref: LocalRef

        /// `true` when the field takes a list.
        let isList: Bool

        /// Gives the error of the call from the URI.
        let error: @Sendable (String) -> KanbanError

        /// The URI of the node in a different board.
        var uri: String {
            OtherBoardRefTests.uri(of: ref)
        }

        /// The field of the `input` object, with the URI as its value.
        var input: String {
            let value = isList ? AddUpdateTaskTests.list(of: [uri]) : #""\#(uri)""#
            return "\(field): \(value)"
        }

        /// The error of the call.
        var expected: KanbanError {
            error(uri)
        }

        /// The name of the field, in the test output.
        var testDescription: String {
            field
        }
    }

    /// Each `addTask` field that takes a node of the current board only.
    static let addTaskCases = [
        InputCase(field: PropertyName.column, ref: .column(slug: ReadinessFixture.todo), isList: false) { uri in
            .notFound(type: .column, reference: uri)
        },
        InputCase(field: PropertyName.tags, ref: .tag(slug: tagSlug), isList: true) { uri in
            .notFound(type: .tag, reference: uri)
        },
        InputCase(field: PropertyName.assignees, ref: .actor(slug: actorSlug), isList: true) { uri in
            .actorNotFound(reference: uri)
        },
    ]

    // MARK: - Helpers

    /// Gives the full URI of a node of a board that is not the fixture board.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The URI text.
    static func uri(of ref: LocalRef) -> String {
        NodeURI(boardKey: DependencyMarkersTests.otherBoardKey, ref: ref).description
    }

    // MARK: - Tests

    @Test(
        "addTask with a URI of a different board in a one-board field gives the not-found error and writes nothing",
        arguments: addTaskCases
    )
    func addTaskRefusesOtherBoardRef(inputCase: InputCase) async throws {
        let field = AddUpdateTaskTests.addTask(with: inputCase.input)
        let error = try await CommentTests.failure(of: field, in: TemporaryDirectory())
        #expect(error == inputCase.expected)
    }

    @Test("addComment with an author URI of a different board gives ACTOR_NOT_FOUND and writes nothing")
    func addCommentRefusesOtherBoardAuthor() async throws {
        let author = Self.uri(of: .actor(slug: Self.actorSlug))
        let task = AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.fixtureTask())
        let field = CommentTests.addComment(to: task, with: #"actor: "\#(author)""#)
        let error = try await CommentTests.failure(of: field, in: TemporaryDirectory())
        #expect(error == .actorNotFound(reference: author))
    }
}
