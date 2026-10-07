import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the name matcher of the forgiving names (plan.md §4.5): each match step, ties, and the never list.
@Suite("Name matcher")
struct NameMatcherTests {
    /// The top-level mutations of plan.md §4.2.
    static let mutations = [
        "initBoard", "updateBoard", "addTask", "updateTask", "moveTask", "completeTask", "assignTask",
        "unassignTask", "tagTask", "untagTask", "deleteTask", "undeleteTask", "undo", "redo", "addColumn",
        "updateColumn", "deleteColumn", "undeleteColumn", "addActor", "updateActor", "deleteActor", "undeleteActor",
        "addTag", "updateTag", "deleteTag", "undeleteTag", "renameTag", "addComment", "updateComment",
        "deleteComment", "undeleteComment",
    ].map { CanonicalName(field: $0) }

    /// The fields of the `Task` type, with their aliases.
    static let taskFields = [
        "id", "body", "created", "updated", "deleted", "shortId", "title", "column", "ordinal", "assignees", "tags",
        "dependsOn", "blockedBy", "blocks", "ready", "virtualTags", "progress", "comments", "started", "completed",
    ].map { CanonicalName(field: $0) }

    /// The fields of the `Board` type. It has `task` and `tasks`, which differ by one letter.
    static let boardFields = [
        "id", "body", "created", "updated", "deleted", "key", "name", "columns", "actors", "tags", "task", "tasks",
        "summary",
    ].map { CanonicalName(field: $0) }

    /// The fields of the `input` object of `moveTask`.
    static let moveTaskInputFields = ["id", "column", "ordinal", "before", "after"].map { CanonicalName(field: $0) }

    /// Gives the match of a top-level mutation name.
    ///
    /// - Parameter name: The name that the agent wrote.
    /// - Returns: The match among the mutations of plan.md §4.2.
    static func mutationMatch(for name: String) -> NameMatch {
        NameMatcher.match(for: name, among: mutations, at: .topLevelMutation)
    }

    /// Gives the match of a name at a position that is not a top-level mutation.
    ///
    /// - Parameters:
    ///   - name: The name that the agent wrote.
    ///   - candidates: The valid names at the position.
    /// - Returns: The match among the candidates.
    static func fieldMatch(for name: String, among candidates: [CanonicalName]) -> NameMatch {
        NameMatcher.match(for: name, among: candidates, at: .anyOther)
    }

    // MARK: - Step 1: the exact name

    @Test("The exact name gives itself")
    func exactNameGivesItself() {
        #expect(Self.mutationMatch(for: "addTask") == .found(canonical: "addTask"))
        #expect(Self.fieldMatch(for: "title", among: Self.taskFields) == .found(canonical: "title"))
    }

    // MARK: - Step 2: case and style

    @Test(
        "The same name in a different case or style gives the canonical name",
        arguments: [("Title", "title"), ("TITLE", "title"), ("short_id", "shortId"), ("short-id", "shortId"),
                    ("SHORTID", "shortId"), ("ShortId", "shortId"), ("depends_on", "dependsOn")]
    )
    func caseAndStyleGiveCanonicalName(name: String, expected: String) {
        #expect(Self.fieldMatch(for: name, among: Self.taskFields) == .found(canonical: expected))
    }

    @Test("An enum value in a different case gives the canonical value", arguments: ["done", "Done", "DONE"])
    func enumValueCaseGivesCanonicalValue(name: String) {
        let values = ["TODO", "DOING", "DONE"].map { CanonicalName(name: $0, aliases: []) }
        #expect(Self.fieldMatch(for: name, among: values) == .found(canonical: "DONE"))
    }

    // MARK: - Step 3: singular and plural

    @Test(
        "The singular or plural form gives the canonical name",
        arguments: [("tag", "tags"), ("assignee", "assignees"), ("comment", "comments"), ("blockedBys", "blockedBy")]
    )
    func numberGivesCanonicalName(name: String, expected: String) {
        #expect(Self.fieldMatch(for: name, among: Self.taskFields) == .found(canonical: expected))
    }

    @Test("A plural mutation name gives the singular mutation")
    func pluralMutationGivesSingular() {
        #expect(Self.mutationMatch(for: "deleteTasks") == .found(canonical: "deleteTask"))
    }

    @Test("A plural that ends in ies gives the form that ends in y")
    func iesPluralGivesY() {
        let candidates = [CanonicalName(name: "summary", aliases: [])]
        #expect(Self.fieldMatch(for: "summaries", among: candidates) == .found(canonical: "summary"))
    }

    // MARK: - Step 4: word order and verb synonyms

    @Test(
        "The other word order and the verb synonyms give the canonical mutation",
        arguments: [
            ("taskAdd", "addTask"), ("createTask", "addTask"), ("create_task", "addTask"), ("newTask", "addTask"),
            ("insertTask", "addTask"), ("TaskCreate", "addTask"), ("removeTask", "deleteTask"),
            ("rmTask", "deleteTask"), ("delTask", "deleteTask"), ("archiveTask", "deleteTask"),
            ("taskArchive", "deleteTask"), ("editTask", "updateTask"), ("modifyTask", "updateTask"),
            ("setTask", "updateTask"), ("patchTask", "updateTask"), ("mvTask", "moveTask"),
            ("doneTask", "completeTask"), ("finishTask", "completeTask"), ("closeTask", "completeTask"),
            ("labelTask", "tagTask"), ("unlabelTask", "untagTask"), ("restoreTask", "undeleteTask"),
            ("unarchiveTask", "undeleteTask"), ("recoverTask", "undeleteTask"), ("boardInit", "initBoard"),
            ("tag_rename", "renameTag"), ("createTasks", "addTask"),
        ]
    )
    func wordOrderAndSynonymsGiveMutation(name: String, expected: String) {
        #expect(Self.mutationMatch(for: name) == .found(canonical: expected))
    }

    @Test("The word order and the verb synonyms apply only to a top-level mutation")
    func wordOrderOnlyForMutation() {
        let candidates = [CanonicalName(name: "addTask", aliases: [])]
        #expect(Self.fieldMatch(for: "taskAdd", among: candidates) == .notFound)
        #expect(Self.fieldMatch(for: "createTask", among: candidates) == .notFound)
    }

    // MARK: - Step 5: the alias table

    @Test(
        "An alias of a field gives the field",
        arguments: [("description", "body"), ("desc", "body"), ("text", "body"), ("content", "body"),
                    ("Desc", "body"), ("status", "column"), ("labels", "tags")]
    )
    func aliasGivesField(name: String, expected: String) {
        #expect(Self.fieldMatch(for: name, among: Self.taskFields) == .found(canonical: expected))
    }

    @Test("The task_id alias of an input field gives id, and status gives column")
    func inputFieldAliases() {
        #expect(Self.fieldMatch(for: "task_id", among: Self.moveTaskInputFields) == .found(canonical: "id"))
        #expect(Self.fieldMatch(for: "status", among: Self.moveTaskInputFields) == .found(canonical: "column"))
    }

    @Test("The label alias gives tag")
    func labelAliasGivesTag() {
        let candidates = [CanonicalName(field: "tag"), CanonicalName(field: "id")]
        #expect(Self.fieldMatch(for: "label", among: candidates) == .found(canonical: "tag"))
    }

    // MARK: - Step 6: one wrong letter

    @Test(
        "One changed, added, or removed letter gives the canonical name",
        arguments: [("titls", "title"), ("tite", "title"), ("titlex", "title"), ("ordnal", "ordinal"),
                    ("redy", "ready")]
    )
    func closeSpellingGivesCanonicalName(name: String, expected: String) {
        #expect(Self.fieldMatch(for: name, among: Self.taskFields) == .found(canonical: expected))
    }

    @Test("A close spelling of a mutation gives the mutation")
    func closeSpellingOfMutation() {
        #expect(Self.mutationMatch(for: "moveTsk") == .found(canonical: "moveTask"))
    }

    @Test("A name of fewer than 4 letters does not match by close spelling")
    func shortNameHasNoCloseSpelling() {
        #expect(Self.fieldMatch(for: "nme", among: Self.boardFields) == .notFound)
        #expect(Self.fieldMatch(for: "ky", among: Self.boardFields) == .notFound)
    }

    @Test("A name with two wrong letters does not match")
    func twoWrongLettersDoNotMatch() {
        #expect(Self.fieldMatch(for: "tilte", among: Self.taskFields) == .notFound)
    }

    // MARK: - Ties

    @Test("A tie at a step gives the list of matches, not one name")
    func tieGivesListOfMatches() {
        #expect(Self.fieldMatch(for: "taskz", among: Self.boardFields) == .tie(matches: ["task", "tasks"]))
    }

    @Test("A tie of two styles of one name gives the list of matches")
    func styleTieGivesListOfMatches() {
        let candidates = [CanonicalName(name: "taskId", aliases: []), CanonicalName(name: "task_id", aliases: [])]
        #expect(Self.fieldMatch(for: "TASKID", among: candidates) == .tie(matches: ["taskId", "task_id"]))
    }

    @Test("The first step with one match wins over a later step")
    func earlierStepWins() {
        // `tasks` is an exact name at step 1, and `task` is one letter away at step 6.
        #expect(Self.fieldMatch(for: "tasks", among: Self.boardFields) == .found(canonical: "tasks"))
    }

    // MARK: - The never list

    @Test("createBoard does not give initBoard")
    func createBoardDoesNotGiveInitBoard() {
        #expect(Self.mutationMatch(for: "createBoard") == .notFound)
        #expect(Self.mutationMatch(for: "boardCreate") == .notFound)
    }

    @Test("The never list blocks a mapping that a step gives, but not the exact name")
    func neverListBlocksStepMatch() {
        // The alias makes step 5 give `initBoard` for `createBoard`. The never list must block it.
        let candidates = [CanonicalName(name: "initBoard", aliases: ["createBoard"])]
        #expect(NameMatcher.match(for: "createBoard", among: candidates, at: .topLevelMutation) == .notFound)
        #expect(NameMatcher.match(for: "initBoard", among: candidates, at: .topLevelMutation)
            == .found(canonical: "initBoard"))
    }

    @Test("The never list does not block a mapping that keeps the forbidden word")
    func neverListKeepsMappingWithBothWords() {
        let candidates = [CanonicalName(name: "createInitBoard", aliases: [])]
        #expect(NameMatcher.match(for: "createInitBoards", among: candidates, at: .topLevelMutation)
            == .found(canonical: "createInitBoard"))
    }

    @Test("A name with no match gives no match")
    func unknownNameGivesNoMatch() {
        #expect(Self.fieldMatch(for: "frobnicate", among: Self.taskFields) == .notFound)
        #expect(Self.mutationMatch(for: "frobnicateTask") == .notFound)
    }
}
