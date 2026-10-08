import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the tag mutations and the tag rename (plan.md §4.2, §6.1, §6.2): `addTag`, `updateTag`, `deleteTag`,
/// `undeleteTag`, and `renameTag`.
///
/// These tests are the GraphQL form of the Rust tag tests: the tag dispatch tests of `dispatch/tests/actors_tags.rs`,
/// and the tests of `tag/update.rs` and `tag/delete.rs`. Each test uses the fixture logs of ``KanbanGraphTests``: the
/// board, the column `todo`, and one task in `todo`.
///
/// Three rules are different from Rust. A rename writes a redirect on the old tag and changes no task body; the Rust
/// code wrote the new marker into each body. A rename to a tag that exists is a merge; the Rust code gave an error. A
/// delete makes a tombstone and changes no task body, and the tasks lose the tag at read time; the Rust code removed
/// the markers from each body.
@Suite("Tag mutations")
struct TagMutationTests {
    /// The slug of the first tag of a test.
    static let bug = "bug"

    /// The slug of the rename target of ``bug``.
    static let defect = "defect"

    /// The slug of the end of a rename chain.
    private static let issue = "issue"

    /// The local ref of ``bug``.
    private static let bugTag = LocalRef.tag(slug: bug)

    /// The local ref of ``defect``.
    private static let defectTag = LocalRef.tag(slug: defect)

    /// A tag name with a space and capitals.
    private static let spacedName = "Bug Fix"

    /// The stored name of ``spacedName``: the tag name rule changes the space to `_`.
    private static let storedSpacedName = "Bug_Fix"

    /// The slug of ``spacedName``.
    private static let spacedSlug = "bug-fix"

    /// A slug that names no tag.
    private static let unknownTag = "nothing"

    /// A task body with a marker of ``bug`` between other words.
    private static let markedBody = "Login broken #bug please fix"

    /// The selection of a tag field that gives the id, the name, and the color.
    static let tagSelection = "{ id name color }"

    /// The `input` field that gives the color ``ColumnActorTests/green``.
    static let greenInput = #"color: "\#(ColumnActorTests.green)""#

    /// The mutation document that adds ``bug`` and renames it to ``defect``.
    static let renameBugToDefect = AddUpdateTaskTests.mutation(
        of: addTag(named: bug),
        renameTag(from: bug, to: defect)
    )

    /// The mutation document that adds ``bug``.
    private static let addBug = AddUpdateTaskTests.mutation(of: addTag(named: bug))

    /// The response of a query of the tasks that match a filter, when one task matches.
    private static let oneMatch = #"{"data":{"board":{"tasks":{"totalCount":1}}}}"#

    /// The `input` of `addTag` that gives a name that gives an empty slug, and the `input` that gives no name and no
    /// id, each with the name that the `INVALID_TAG_NAME` error gives.
    private static let invalidNameInputs = [
        (#"name: "\#(ColumnActorTests.emptySlugName)""#, ColumnActorTests.emptySlugName),
        ("", ""),
    ]

    // MARK: - Helpers

    /// Makes an `addTag` field.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func addTag(with input: String, selecting selection: String = tagSelection) -> String {
        "addTag(input: { \(input) }) \(selection)"
    }

    /// Makes an `addTag` field that gives only the name of the tag.
    ///
    /// - Parameter name: The tag name.
    /// - Returns: The field.
    static func addTag(named name: String) -> String {
        addTag(with: #"name: "\#(name)""#)
    }

    /// Makes a field of a tag mutation whose `input` names ``bug``.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `deleteTag`.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func bugField(
        _ name: String,
        with input: String = "",
        selecting selection: String = AddUpdateTaskTests.idSelection
    ) -> String {
        CommentTests.nodeField(name, naming: bug, with: input, selecting: selection)
    }

    /// Makes a `renameTag` field.
    ///
    /// - Parameters:
    ///   - source: The tag to rename, as the field writes it.
    ///   - target: The new tag name.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    static func renameTag(
        from source: String,
        to target: String,
        selecting selection: String = tagSelection
    ) -> String {
        #"renameTag(input: { from: "\#(source)", to: "\#(target)" }) \#(selection)"#
    }

    /// Makes the `tags` part of an `addTask` input with one tag.
    ///
    /// - Parameter tag: The tag name.
    /// - Returns: The `input` field.
    private static func tags(_ tag: String) -> String {
        #"tags: ["\#(tag)"]"#
    }

    /// Gives the JSON of a tag as ``tagSelection`` selects it.
    ///
    /// - Parameters:
    ///   - slug: The slug of the tag.
    ///   - name: The name of the tag, or `nil` for the slug.
    ///   - color: The color of the tag, or `nil` for the auto color of the slug.
    /// - Returns: The JSON object text.
    private static func tagJSON(_ slug: String, named name: String? = nil, color: String? = nil) -> String {
        let id = ColumnActorTests.id(of: .tag(slug: slug))
        return #"{"color":"\#(color ?? AutoColor.color(forText: slug))","id":"\#(id)","name":"\#(name ?? slug)"}"#
    }

    /// Gives the JSON of a mutation field that selects only the id of a tag.
    ///
    /// - Parameters:
    ///   - field: The name of the mutation field.
    ///   - ref: The local ref of the tag.
    /// - Returns: The response JSON text.
    private static func idResponse(of field: String, naming ref: LocalRef) -> String {
        #"{"data":{"\#(field)":{"id":"\#(ColumnActorTests.id(of: ref))"}}}"#
    }

    /// Gives the `set` part of the patch of a tag that a mutation adds with no color: the name and the auto color.
    ///
    /// - Parameter slug: The slug of the tag. The slug is also the name.
    /// - Returns: The `set` part.
    private static func autoColorSetting(of slug: String) -> [String: PatchValue] {
        ColumnActorTests.setting(name: slug, color: AutoColor.color(forText: slug))
    }

    /// Gives the patch that sets the color ``ColumnActorTests/green`` of a tag.
    ///
    /// - Parameter ref: The local ref of the tag.
    /// - Returns: The patch.
    private static func greenPatch(of ref: LocalRef) throws -> PatchInput {
        try PatchInput(node: ref, set: [PropertyName.color: .string(ColumnActorTests.green)])
    }

    /// Gives the redirect patch of a rename: a `set` of `renamedTo`.
    ///
    /// - Parameters:
    ///   - source: The local ref of the renamed tag.
    ///   - target: The slug of the rename target.
    /// - Returns: The patch.
    private static func redirect(of source: LocalRef, to target: String) throws -> PatchInput {
        try PatchInput(node: source, set: [PropertyName.renamedTo: .ref(.local(.tag(slug: target)))])
    }

    /// Gives the last patch of the log of a tag.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the tag.
    ///   - directory: The temporary repo directory.
    /// - Returns: The patch, or `nil` when the tag has no log.
    private static func lastPatch(of ref: LocalRef, in directory: TemporaryDirectory) throws -> PatchInput? {
        try ColumnActorTests.patches(of: ref, in: directory).last
    }

    /// Runs a setup document on a new engine of the fixture repo.
    ///
    /// - Parameters:
    ///   - setup: The setup document.
    ///   - directory: The temporary repo directory.
    /// - Returns: The engine.
    private static func graph(after setup: String, in directory: TemporaryDirectory) async throws -> KanbanGraph {
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(setup, on: graph)
        return graph
    }

    /// Adds a task on a new engine of the fixture repo.
    ///
    /// - Parameters:
    ///   - input: The other fields of the `addTask` input.
    ///   - directory: The temporary repo directory.
    /// - Returns: The engine, and the ULID of the added task.
    private static func addedTask(
        with input: String,
        in directory: TemporaryDirectory
    ) async throws -> (graph: KanbanGraph, task: ULID) {
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let response = try await CommentTests.run(AddUpdateTaskTests.addTask(with: input), on: graph)
        return (graph, try AddUpdateTaskTests.firstTask(in: response))
    }

    /// Gives the response of a query of the tag names of a task.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func tagNames(of task: ULID, on graph: KanbanGraph) async throws -> String {
        try await CommentTests.respond(toQueryOf: task, selecting: "{ tags { name } }", on: graph)
    }

    /// Gives the response of ``tagNames(of:on:)`` for one tag.
    ///
    /// - Parameter name: The name of the tag.
    /// - Returns: The response JSON text.
    private static func tagNamesResponse(_ name: String) -> String {
        #"{"data":{"board":{"task":{"tags":[{"name":"\#(name)"}]}}}}"#
    }

    /// Gives the response of a query of the number of tasks that match a filter. The query keeps the done tasks,
    /// because the fixture column `todo` is the terminal column.
    ///
    /// - Parameters:
    ///   - filter: The filter text.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func respond(toFilter filter: String, on graph: KanbanGraph) async throws -> String {
        let query = #"{ board { tasks(filter: "\#(filter)", excludeDone: false) { totalCount } } }"#
        return try await KanbanGraphTests.execute(query, on: graph)
    }

    // MARK: - addTag

    @Test("addTag with a name makes the tag with the auto color, and writes one patch with the name and the color")
    func addTagWithName() async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respond(to: Self.addBug, onFixtureIn: directory)
        #expect(response == #"{"data":{"addTag":\#(Self.tagJSON(Self.bug))}}"#)
        let expected = try PatchInput(node: Self.bugTag, set: Self.autoColorSetting(of: Self.bug))
        #expect(try ColumnActorTests.patches(of: Self.bugTag, in: directory) == [expected])
    }

    @Test("addTag with a color and a body writes one patch with the name, the color, and the body diff")
    func addTagWithColorAndBody() async throws {
        let directory = try TemporaryDirectory()
        let input = #"name: "\#(Self.bug)", color: "\#(ColumnActorTests.red)", body: $body"#
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.bodyMutation(of: Self.addTag(with: input, selecting: "{ color body }")),
            with: ColumnActorTests.bodyVariables,
            onFixtureIn: directory
        )
        let tag = #"{"body":"\#(ColumnActorTests.bodyJSON)","color":"\#(ColumnActorTests.red)"}"#
        #expect(response == #"{"data":{"addTag":\#(tag)}}"#)
        let set = ColumnActorTests.setting(name: Self.bug, color: ColumnActorTests.red)
        let expected = try ColumnActorTests.bodyPatch(of: Self.bugTag, setting: set)
        #expect(try ColumnActorTests.patches(of: Self.bugTag, in: directory) == [expected])
    }

    @Test("addTag with only an id uses the id as the name")
    func addTagWithOnlyID() async throws {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(of: Self.addTag(with: #"id: "\#(Self.bug)""#))
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"addTag":\#(Self.tagJSON(Self.bug))}}"#)
    }

    @Test("addTag stores the name with the tag name rule, and the id is the slug of the name")
    func addTagNormalizesName() async throws {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(of: Self.addTag(named: Self.spacedName))
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let tag = Self.tagJSON(Self.spacedSlug, named: Self.storedSpacedName)
        #expect(response == #"{"data":{"addTag":\#(tag)}}"#)
    }

    @Test("addTag with the slug of a tag that exists returns that tag and writes nothing")
    func addTagIsIdempotent() async throws {
        let directory = try TemporaryDirectory()
        let input = #"name: "\#(Self.bug.uppercased())", color: "\#(ColumnActorTests.red)""#
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.addTag(with: input)),
            after: Self.addBug,
            in: directory
        )
        #expect(response == #"{"data":{"addTag":\#(Self.tagJSON(Self.bug))}}"#)
    }

    @Test("addTag with a slug that a rename redirects returns the rename target and writes nothing")
    func addTagFollowsRedirect() async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: Self.addBug,
            after: Self.renameBugToDefect,
            in: directory
        )
        let defect = Self.tagJSON(Self.defect, color: AutoColor.color(forText: Self.bug))
        #expect(response == #"{"data":{"addTag":\#(defect)}}"#)
    }

    @Test("addTag with the slug of a tombstoned tag writes delete false and returns the live tag")
    func addTagRevivesTombstone() async throws {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(
            of: "first: " + Self.addTag(named: Self.bug),
            Self.bugField("deleteTag"),
            "second: " + Self.addTag(named: Self.bug)
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""second":\#(Self.tagJSON(Self.bug))}}"#))
        #expect(try ColumnActorTests.lastPatch(of: Self.bugTag, isDelete: false, in: directory))
    }

    @Test(
        "addTag with a name that gives an empty slug, or with no name and no id, gives INVALID_TAG_NAME",
        arguments: invalidNameInputs
    )
    func addTagInvalidName(input: String, name: String) async throws {
        let directory = try TemporaryDirectory()
        let error = try await CommentTests.failure(of: Self.addTag(with: input), in: directory)
        #expect(error == .invalidTagName(name: name))
    }

    // MARK: - updateTag

    @Test("updateTag changes the name, the color, and the body, and keeps the slug")
    func updateTagChangesFields() async throws {
        let directory = try TemporaryDirectory()
        let input = #"name: "\#(Self.spacedName)", \#(Self.greenInput), body: $body"#
        let update = Self.bugField("updateTag", with: input, selecting: "{ id name body }")
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.bodyMutation(of: Self.addTag(named: Self.bug), update),
            with: ColumnActorTests.bodyVariables,
            onFixtureIn: directory
        )
        let id = ColumnActorTests.id(of: Self.bugTag)
        let tag = #"{"body":"\#(ColumnActorTests.bodyJSON)","id":"\#(id)","name":"\#(Self.storedSpacedName)"}"#
        #expect(response.hasSuffix(#""updateTag":\#(tag)}}"#))
        let set = ColumnActorTests.setting(name: Self.storedSpacedName, color: ColumnActorTests.green)
        let expected = try ColumnActorTests.bodyPatch(of: Self.bugTag, setting: set)
        #expect(try Self.lastPatch(of: Self.bugTag, in: directory) == expected)
    }

    @Test("updateTag with only a color writes a set of the color, and keeps the name and the body")
    func updateTagColorKeepsOtherFields() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTag(with: #"name: "\#(Self.bug)", body: $body"#)
        let update = Self.bugField("updateTag", with: Self.greenInput, selecting: "{ name body }")
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.bodyMutation(of: add, update),
            with: ColumnActorTests.bodyVariables,
            onFixtureIn: directory
        )
        let tag = #"{"body":"\#(ColumnActorTests.bodyJSON)","name":"\#(Self.bug)"}"#
        #expect(response.hasSuffix(#""updateTag":\#(tag)}}"#))
        #expect(try Self.lastPatch(of: Self.bugTag, in: directory) == Self.greenPatch(of: Self.bugTag))
    }

    @Test("updateTag with an empty body writes the diff to the empty text")
    func updateTagClearsBody() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTag(with: #"name: "\#(Self.bug)", body: $body"#)
        let update = Self.bugField("updateTag", with: #"body: """#, selecting: "{ body }")
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.bodyMutation(of: add, update),
            with: ColumnActorTests.bodyVariables,
            onFixtureIn: directory
        )
        #expect(response.hasSuffix(#""updateTag":{"body":""}}}"#))
        let edit = PatchEdit(body: ReplayTests.diff(from: ColumnActorTests.body, to: ""))
        #expect(try Self.lastPatch(of: Self.bugTag, in: directory) == PatchInput(node: Self.bugTag, edit: edit))
    }

    @Test("updateTag with a slug that a rename redirects changes the rename target")
    func updateTagFollowsRedirect() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.graph(after: Self.renameBugToDefect, in: directory)
        let response = try await CommentTests.run(Self.bugField("updateTag", with: Self.greenInput), on: graph)
        #expect(response == Self.idResponse(of: "updateTag", naming: Self.defectTag))
        #expect(try Self.lastPatch(of: Self.defectTag, in: directory) == Self.greenPatch(of: Self.defectTag))
    }

    @Test("updateTag with a name that gives an empty slug gives INVALID_TAG_NAME and writes nothing")
    func updateTagInvalidName() async throws {
        let directory = try TemporaryDirectory()
        let input = #"name: "\#(ColumnActorTests.emptySlugName)""#
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.bugField("updateTag", with: input)),
            after: Self.addBug,
            in: directory
        )
        #expect(error == .invalidTagName(name: ColumnActorTests.emptySlugName))
    }

    @Test(
        "A tag mutation with an id that names no tag gives NOT_FOUND and writes nothing",
        arguments: ["updateTag", "deleteTag", "undeleteTag"]
    )
    func tagMutationNotFound(name: String) async throws {
        let directory = try TemporaryDirectory()
        let field = CommentTests.nodeField(name, naming: Self.unknownTag)
        let error = try await CommentTests.failure(of: field, in: directory)
        #expect(error == .notFound(type: .tag, reference: Self.unknownTag))
    }

    // MARK: - deleteTag and undeleteTag

    @Test("deleteTag writes delete true, and a task with a marker of the tag loses the tag and keeps its body")
    func deleteTagKeepsTaskBody() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedTask(with: #"body: "\#(Self.markedBody)""#, in: directory)
        let response = try await CommentTests.run(Self.bugField("deleteTag", selecting: "{ deleted }"), on: added.graph)
        #expect(response == #"{"data":{"deleteTag":{"deleted":"\#(KanbanGraphTests.time.rfc3339)"}}}"#)
        #expect(try ColumnActorTests.lastPatch(of: Self.bugTag, isDelete: true, in: directory))
        let selection = "{ body tags { name } }"
        let task = try await CommentTests.respond(toQueryOf: added.task, selecting: selection, on: added.graph)
        #expect(task == #"{"data":{"board":{"task":{"body":"\#(Self.markedBody)","tags":[]}}}}"#)
    }

    @Test("deleteTag with the old slug after renameTag deletes the rename target")
    func deleteTagFollowsRedirect() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.graph(after: Self.renameBugToDefect, in: directory)
        let response = try await CommentTests.run(Self.bugField("deleteTag"), on: graph)
        #expect(response == Self.idResponse(of: "deleteTag", naming: Self.defectTag))
        #expect(try ColumnActorTests.lastPatch(of: Self.defectTag, isDelete: true, in: directory))
    }

    @Test("undeleteTag on a tombstone writes delete false and returns the live tag")
    func undeleteTag() async throws {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(
            of: Self.addTag(named: Self.bug),
            Self.bugField("deleteTag"),
            Self.bugField("undeleteTag", selecting: "{ name deleted }")
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""undeleteTag":{"deleted":null,"name":"\#(Self.bug)"}}}"#))
        #expect(try ColumnActorTests.lastPatch(of: Self.bugTag, isDelete: false, in: directory))
    }

    // MARK: - renameTag

    @Test("renameTag to a new slug writes the new tag with the color and the body of the old tag, then the redirect")
    func renameTagToNewSlug() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTag(with: #"name: "\#(Self.bug)", color: "\#(ColumnActorTests.red)", body: $body"#)
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.bodyMutation(of: add, Self.renameTag(from: Self.bug, to: Self.defect)),
            with: ColumnActorTests.bodyVariables,
            onFixtureIn: directory
        )
        #expect(response.hasSuffix(#""renameTag":\#(Self.tagJSON(Self.defect, color: ColumnActorTests.red))}}"#))
        let set = ColumnActorTests.setting(name: Self.defect, color: ColumnActorTests.red)
        let expected = try ColumnActorTests.bodyPatch(of: Self.defectTag, setting: set)
        #expect(try ColumnActorTests.patches(of: Self.defectTag, in: directory) == [expected])
        #expect(try Self.lastPatch(of: Self.bugTag, in: directory) == Self.redirect(of: Self.bugTag, to: Self.defect))
    }

    @Test("After renameTag, a task with the old tag shows the new tag, and the filters of the two slugs match it")
    func renamedTagShowsOnTask() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedTask(with: Self.tags(Self.bug), in: directory)
        _ = try await CommentTests.run(Self.renameTag(from: Self.bug, to: Self.defect), on: added.graph)
        #expect(try await Self.tagNames(of: added.task, on: added.graph) == Self.tagNamesResponse(Self.defect))
        #expect(try await Self.respond(toFilter: "#\(Self.bug)", on: added.graph) == Self.oneMatch)
        #expect(try await Self.respond(toFilter: "#\(Self.defect)", on: added.graph) == Self.oneMatch)
    }

    @Test("addTask with the old slug after renameTag writes the tag edge to the new tag")
    func addTaskAfterRenameUsesTarget() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.graph(after: Self.renameBugToDefect, in: directory)
        let response = try await CommentTests.run(AddUpdateTaskTests.addTask(with: Self.tags(Self.bug)), on: graph)
        let task = try AddUpdateTaskTests.firstTask(in: response)
        let added = try Self.lastPatch(of: .task(task), in: directory)?.add[PropertyName.tags]
        #expect(added == [.local(Self.defectTag)])
    }

    @Test("After renameTag, Board.tags lists the new tag and not the old tag")
    func renamedTagIsListedOnce() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.graph(after: Self.renameBugToDefect, in: directory)
        let response = try await KanbanGraphTests.execute("{ board { tags { name } } }", on: graph)
        #expect(response == #"{"data":{"board":{"tags":[{"name":"\#(Self.defect)"}]}}}"#)
    }

    @Test("renameTag to a tag that exists writes only the redirect, and the tag keeps its own values")
    func renameTagMergesIntoExistingTag() async throws {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(
            of: "a: " + Self.addTag(named: Self.bug),
            "b: " + Self.addTag(with: #"name: "\#(Self.defect)", \#(Self.greenInput)"#),
            Self.renameTag(from: Self.bug, to: Self.defect)
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""renameTag":\#(Self.tagJSON(Self.defect, color: ColumnActorTests.green))}}"#))
        let added = try PatchInput(
            node: Self.defectTag,
            set: ColumnActorTests.setting(name: Self.defect, color: ColumnActorTests.green)
        )
        #expect(try ColumnActorTests.patches(of: Self.defectTag, in: directory) == [added])
        #expect(try Self.lastPatch(of: Self.bugTag, in: directory) == Self.redirect(of: Self.bugTag, to: Self.defect))
    }

    @Test("renameTag of a renamed slug renames the end of the chain, and a task with the first slug shows the last tag")
    func renameTagChain() async throws {
        let directory = try TemporaryDirectory()
        let added = try await Self.addedTask(with: Self.tags(Self.bug), in: directory)
        _ = try await CommentTests.run(Self.renameTag(from: Self.bug, to: Self.defect), on: added.graph)
        let response = try await CommentTests.run(
            Self.renameTag(from: Self.bug, to: Self.issue, selecting: AddUpdateTaskTests.idSelection),
            on: added.graph
        )
        #expect(response == Self.idResponse(of: "renameTag", naming: .tag(slug: Self.issue)))
        let redirect = try Self.redirect(of: Self.defectTag, to: Self.issue)
        #expect(try Self.lastPatch(of: Self.defectTag, in: directory) == redirect)
        #expect(try await Self.tagNames(of: added.task, on: added.graph) == Self.tagNamesResponse(Self.issue))
    }

    @Test("renameTag that makes a rename cycle gives TAG_RENAME_CYCLE and writes nothing")
    func renameTagCycleIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.renameTag(from: Self.defect, to: Self.bug)),
            after: Self.renameBugToDefect,
            in: directory
        )
        #expect(error == .tagRenameCycle(path: [Self.defect, Self.bug, Self.defect]))
    }

    @Test("renameTag to the slug of the tag itself writes nothing and returns the tag")
    func renameTagToSameSlug() async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.renameTag(from: Self.bug, to: Self.bug.uppercased())),
            after: Self.addBug,
            in: directory
        )
        #expect(response == #"{"data":{"renameTag":\#(Self.tagJSON(Self.bug))}}"#)
    }

    @Test("renameTag from a tag that does not exist gives NOT_FOUND and writes nothing")
    func renameTagUnknownSource() async throws {
        let directory = try TemporaryDirectory()
        let rename = Self.renameTag(from: Self.unknownTag, to: Self.defect)
        let error = try await CommentTests.failure(of: rename, in: directory)
        #expect(error == .notFound(type: .tag, reference: Self.unknownTag))
    }

    @Test("renameTag to a name that gives an empty slug gives INVALID_TAG_NAME and writes nothing")
    func renameTagInvalidTarget() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.renameTag(from: Self.bug, to: ColumnActorTests.emptySlugName)),
            after: Self.addBug,
            in: directory
        )
        #expect(error == .invalidTagName(name: ColumnActorTests.emptySlugName))
    }
}
