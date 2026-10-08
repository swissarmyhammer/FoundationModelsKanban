import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the comment mutations (plan.md §3.2, §4.2): `addComment`, `updateComment`, `deleteComment`, and
/// `undeleteComment`.
///
/// These tests are the GraphQL form of the Rust comment dispatch tests (`dispatch/tests/comments.rs`) and of the
/// not-found and order tests of `comment/add.rs`, `comment/update.rs`, `comment/delete.rs`, and `comment/list.rs`.
/// Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and one task in `todo`.
///
/// Two rules are different from Rust. A comment is a full node, so `updateComment` and `deleteComment` need only the
/// comment id, not also the task id. An `actor` that names no actor makes the actor in the same call; the Rust code
/// gave an error.
@Suite("Comment mutations")
struct CommentTests {
    /// The body of a comment that a test adds.
    static let body = QueryFixture.commentBody

    /// The body of a second comment that a test adds.
    private static let laterBody = "Ship it."

    /// The new body of a comment in an update test.
    static let editedBody = "Edited."

    /// The slug of an actor that a test adds before the comment.
    private static let alice = "alice"

    /// The name of an actor that the board does not have.
    private static let newActorName = "Bob Smith"

    /// The slug of ``newActorName``.
    private static let newActorSlug = "bob-smith"

    /// A name that gives an empty slug.
    private static let emptySlugName = "---"

    /// A ref that names no task and no comment.
    private static let unknownRef = "^zzzzzzz"

    /// The selection of a task field that gives the bodies of its comments.
    private static let commentsSelection = "{ comments { body } }"

    // MARK: - Helpers

    /// Makes an `addComment` field on a task.
    ///
    /// - Parameters:
    ///   - task: The task ref as the field writes it, for example `^ajv8v4t`.
    ///   - body: The body of the comment.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    static func addComment(
        to task: String,
        saying body: String = body,
        with input: String = "",
        selecting selection: String = "{ id }"
    ) -> String {
        #"addComment(input: { task: "\#(task)", body: "\#(body)" \#(input) }) \#(selection)"#
    }

    /// Makes an `addComment` field on the fixture task.
    ///
    /// - Parameters:
    ///   - input: The other fields of the `input` object.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func addFixtureComment(
        with input: String,
        selecting selection: String = "{ id }"
    ) throws -> String {
        let task = AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.fixtureTask())
        return addComment(to: task, with: input, selecting: selection)
    }

    /// Makes a field of a mutation whose `input` names one node, for example a comment or a tag.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `deleteComment`.
    ///   - node: The node ref as the field writes it.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    static func nodeField(
        _ name: String,
        naming node: String,
        with input: String = "",
        selecting selection: String = "{ id }"
    ) -> String {
        #"\#(name)(input: { id: "\#(node)" \#(input) }) \#(selection)"#
    }

    /// Runs a mutation document with one field on an engine.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    static func run(_ field: String, on graph: KanbanGraph) async throws -> String {
        try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: field), on: graph)
    }

    /// Runs a mutation document with one field that fails on the fixture repo, and gives its error.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - directory: The temporary repo directory.
    /// - Returns: The error of the first GraphQL error of the response.
    static func failure(of field: String, in directory: TemporaryDirectory) async throws -> KanbanError {
        try await ColumnActorTests.failure(of: AddUpdateTaskTests.mutation(of: field), in: directory)
    }

    /// Runs a query of one task of the board, `Board.task`.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The query names it by `^` and the short id.
    ///   - selection: The selection of the task field.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    static func respond(
        toQueryOf task: ULID,
        selecting selection: String,
        on graph: KanbanGraph
    ) async throws -> String {
        try await KanbanGraphTests.execute(taskQuery(of: task, selecting: selection), on: graph)
    }

    /// Makes a query of one task of the board, `Board.task`.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The query names it by `^` and the short id.
    ///   - selection: The selection of the task field.
    /// - Returns: The query document.
    static func taskQuery(of task: ULID, selecting selection: String) -> String {
        #"{ board { task(id: "\#(AddUpdateTaskTests.sigilRef(of: task))") \#(selection) } }"#
    }

    /// Gives the bodies of the comments of a task, as `Task.comments` lists them.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func commentBodies(of task: ULID, on graph: KanbanGraph) async throws -> String {
        try await respond(toQueryOf: task, selecting: commentsSelection, on: graph)
    }

    /// Gives the response of ``commentBodies(of:on:)`` for some comment bodies.
    ///
    /// - Parameter bodies: The bodies of the comments, in the order of the list.
    /// - Returns: The response JSON text.
    private static func commentBodiesResponse(_ bodies: String...) -> String {
        let comments = bodies.map { body in #"{"body":"\#(body)"}"# }.joined(separator: ",")
        return #"{"data":{"board":{"task":{"comments":[\#(comments)]}}}}"#
    }

    /// Gives the ULIDs of the comments that have a log in a repo.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The ULIDs, in increasing order.
    private static func comments(in directory: TemporaryDirectory) throws -> [ULID] {
        try BoardMutationTests.storedRefs(inRepoAt: directory.url).compactMap { ref in
            if case .comment(let ulid) = ref { ulid } else { nil }
        }
        .sorted()
    }

    /// Gives the ULID of the one comment of a repo.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The ULID of the first comment.
    private static func firstComment(in directory: TemporaryDirectory) throws -> ULID {
        try #require(try comments(in: directory).first)
    }

    /// Adds one comment with the body ``body`` to the fixture task.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The engine, the ULID of the fixture task, and the ULID of the comment.
    private static func addedComment(
        in directory: TemporaryDirectory
    ) async throws -> (graph: KanbanGraph, task: ULID, comment: ULID) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        _ = try await run(addComment(to: AddUpdateTaskTests.sigilRef(of: fixture.task)), on: fixture.graph)
        return (fixture.graph, fixture.task, try firstComment(in: directory))
    }

    // MARK: - addComment

    @Test("addComment returns the comment with id, shortId, author, task, and body, and writes one comment patch")
    func addCommentReturnsComment() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let selection = "{ id shortId body author { id } task { id } }"
        let add = Self.addComment(to: AddUpdateTaskTests.sigilRef(of: fixture.task), selecting: selection)
        let response = try await Self.run(add, on: fixture.graph)
        let comment = try Self.firstComment(in: directory)
        let author = KanbanGraphTests.sessionActor.ref
        let json = #"{"author":{"id":"\#(ColumnActorTests.id(of: author))"},"body":"\#(Self.body)","#
            + #""id":"\#(ColumnActorTests.id(of: .comment(comment)))","shortId":"\#(ShortID(of: comment).value)","#
            + #""task":{"id":"\#(ColumnActorTests.id(of: .task(fixture.task)))"}}"#
        #expect(response == #"{"data":{"addComment":\#(json)}}"#)
        let expected = try PatchInput(
            node: .comment(comment),
            set: [PropertyName.task: .ref(.local(.task(fixture.task))), PropertyName.author: .ref(.local(author))],
            edit: PatchEdit(body: ReplayTests.diff(from: "", to: Self.body))
        )
        #expect(try ColumnActorTests.patches(of: .comment(comment), in: directory) == [expected])
    }

    @Test("addComment with an actor that the board has makes that actor the author, and writes no actor patch")
    func addCommentByKnownActor() async throws {
        let directory = try TemporaryDirectory()
        let addActor = #"addActor(input: { name: "\#(Self.alice)" }) { id }"#
        let add = try Self.addFixtureComment(with: #"actor: "\#(Self.alice)""#, selecting: "{ author { id } }")
        let mutation = AddUpdateTaskTests.mutation(of: addActor, add)
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let actor = LocalRef.actor(slug: Self.alice)
        #expect(response.hasSuffix(#""addComment":{"author":{"id":"\#(ColumnActorTests.id(of: actor))"}}}}"#))
        #expect(try ColumnActorTests.patches(of: actor, in: directory).count == 1)
        let commentPatch = try ColumnActorTests.patches(of: .comment(Self.firstComment(in: directory)), in: directory)
        #expect(commentPatch.first?.set[PropertyName.author] == .ref(.local(actor)))
    }

    @Test("addComment with an actor that names no actor makes the actor in the same call")
    func addCommentMakesUnknownActor() async throws {
        let directory = try TemporaryDirectory()
        let input = #"actor: "\#(Self.newActorName)""#
        let add = try Self.addFixtureComment(with: input, selecting: "{ author { id name } }")
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: add),
            onFixtureIn: directory
        )
        let actor = LocalRef.actor(slug: Self.newActorSlug)
        let author = #"{"id":"\#(ColumnActorTests.id(of: actor))","name":"\#(Self.newActorName)"}"#
        #expect(response == #"{"data":{"addComment":{"author":\#(author)}}}"#)
        let expected = try PatchInput(node: actor, set: [PropertyName.name: .string(Self.newActorName)])
        #expect(try ColumnActorTests.patches(of: actor, in: directory) == [expected])
    }

    @Test("addComment with an actor URI that names no actor gives ACTOR_NOT_FOUND and writes nothing")
    func addCommentUnknownActorURI() async throws {
        let directory = try TemporaryDirectory()
        let actorURI = ColumnActorTests.id(of: .actor(slug: Self.newActorSlug))
        let error = try await Self.failure(of: Self.addFixtureComment(with: #"actor: "\#(actorURI)""#), in: directory)
        #expect(error == .actorNotFound(reference: actorURI))
    }

    @Test("addComment with an actor name that gives an empty slug gives INVALID_SLUG and writes nothing")
    func addCommentInvalidActorName() async throws {
        let directory = try TemporaryDirectory()
        let input = #"actor: "\#(Self.emptySlugName)""#
        let error = try await Self.failure(of: Self.addFixtureComment(with: input), in: directory)
        #expect(error == .invalidSlug(name: Self.emptySlugName))
    }

    @Test("addComment on a task that does not exist gives NOT_FOUND and writes nothing")
    func addCommentUnknownTask() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(of: Self.addComment(to: Self.unknownRef), in: directory)
        #expect(error == .notFound(type: .task, reference: Self.unknownRef))
    }

    // MARK: - Task.comments

    @Test("An added comment is in the comments of its task")
    func addedCommentIsListed() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedComment(in: directory)
        let response = try await Self.commentBodies(of: added.task, on: added.graph)
        #expect(response == Self.commentBodiesResponse(Self.body))
    }

    @Test("Task.comments lists the live comments of the task, oldest first")
    func commentsAreOldestFirst() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let task = AddUpdateTaskTests.sigilRef(of: fixture.task)
        let mutation = AddUpdateTaskTests.mutation(
            of: "first: " + Self.addComment(to: task),
            "second: " + Self.addComment(to: task, saying: Self.laterBody)
        )
        _ = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        let response = try await Self.commentBodies(of: fixture.task, on: fixture.graph)
        #expect(response == Self.commentBodiesResponse(Self.body, Self.laterBody))
    }

    // MARK: - updateComment

    @Test("updateComment with only the comment id writes the body diff, and keeps the author")
    func updateCommentByIDOnly() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedComment(in: directory)
        let update = Self.nodeField(
            MutationName.updateComment,
            naming: AddUpdateTaskTests.sigilRef(of: added.comment),
            with: #"body: "\#(Self.editedBody)""#,
            selecting: "{ body author { id } }"
        )
        let response = try await Self.run(update, on: added.graph)
        let author = ColumnActorTests.id(of: KanbanGraphTests.sessionActor.ref)
        let json = #"{"author":{"id":"\#(author)"},"body":"\#(Self.editedBody)"}"#
        #expect(response == #"{"data":{"updateComment":\#(json)}}"#)
        let edit = PatchEdit(body: ReplayTests.diff(from: Self.body, to: Self.editedBody))
        let expected = try PatchInput(node: .comment(added.comment), edit: edit)
        #expect(try ColumnActorTests.patches(of: .comment(added.comment), in: directory).last == expected)
    }

    @Test(
        "A comment mutation with an id that names no comment gives NOT_FOUND and writes nothing",
        arguments: [MutationName.updateComment, MutationName.deleteComment, MutationName.undeleteComment]
    )
    func commentMutationNotFound(name: String) async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(of: Self.nodeField(name, naming: Self.unknownRef), in: directory)
        #expect(error == .notFound(type: .comment, reference: Self.unknownRef))
    }

    // MARK: - deleteComment and undeleteComment

    @Test("deleteComment with only the comment URI makes a tombstone, and the task does not list it")
    func deleteCommentByIDOnly() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedComment(in: directory)
        let comment = ColumnActorTests.id(of: .comment(added.comment))
        let delete = Self.nodeField(MutationName.deleteComment, naming: comment, selecting: "{ deleted }")
        let response = try await Self.run(delete, on: added.graph)
        #expect(response == #"{"data":{"deleteComment":{"deleted":"\#(KanbanGraphTests.time.rfc3339)"}}}"#)
        #expect(try ColumnActorTests.lastPatch(of: .comment(added.comment), isDelete: true, in: directory))
        let listed = try await Self.commentBodies(of: added.task, on: added.graph)
        #expect(listed == Self.commentBodiesResponse())
    }

    @Test("undeleteComment on a tombstone writes delete false, and the task lists the comment again")
    func undeleteTombstonedComment() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedComment(in: directory)
        let comment = AddUpdateTaskTests.sigilRef(of: added.comment)
        _ = try await Self.run(Self.nodeField(MutationName.deleteComment, naming: comment), on: added.graph)
        let undelete = Self.nodeField(MutationName.undeleteComment, naming: comment, selecting: "{ body deleted }")
        let response = try await Self.run(undelete, on: added.graph)
        #expect(response == #"{"data":{"undeleteComment":{"body":"\#(Self.body)","deleted":null}}}"#)
        #expect(try ColumnActorTests.lastPatch(of: .comment(added.comment), isDelete: false, in: directory))
        let listed = try await Self.commentBodies(of: added.task, on: added.graph)
        #expect(listed == Self.commentBodiesResponse(Self.body))
    }
}
