import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// One removed Rust parameter in one document: the call runs, and the response has one warning.
struct RemovedParameterCase: Sendable, CustomTestStringConvertible {
    /// The document that writes the removed parameter.
    let document: String

    /// The key in `data` of the field that must give a value.
    let resultKey: String

    /// The text of the warning that the response must give.
    let warning: String

    /// The name of the case in the test report.
    var testDescription: String {
        document
    }
}

/// One removed Rust parameter whose value is a variable: the document, the values of its variables, the text that the
/// rewrite makes, and the result and the warning that the call gives.
struct RemovedVariableCase: Sendable, CustomTestStringConvertible {
    /// The document that gives a variable as the value of the removed parameter.
    let document: String

    /// The values of the variables of the document.
    let variables: [String: Map]

    /// The text that the rewrite must make from the document.
    let rewrittenText: String

    /// The key in `data` of the field that must give a value.
    let resultKey: String

    /// The text of the warning that the response must give.
    let warning: String

    /// The name of the case in the test report.
    var testDescription: String {
        document
    }
}

/// Tests the removed Rust parameters and the error for a name with no match (divergence.md Q12 as P4 changed it,
/// N5).
///
/// A removed Rust parameter is ignored: the call runs, and the response gives a "removed" warning in
/// `extensions.warnings`. A name that matches nothing still fails, and the error lists the canonical names of the
/// position. Each test runs on the fixture board of ``KanbanGraphTests`` in a temporary repo.
@Suite("Removed Rust parameters and the error for a name with no match", .watcherBudget)
struct RemovedParameterTests {
    /// The code of each warning of a removed parameter.
    static let warningCode = "REMOVED_PARAMETER"

    /// The warning text of `due` and `scheduled`, after the name in back quotes.
    private static let noDateText = " is removed, with no replacement: write the date in the body. The call ignored it."

    /// The removed `due` parameter and its value, as an `input` field.
    private static let removedDue = #"due: "2026-01-01""#

    /// The text before the names in the error of an `input` field of `AddTaskInput` with no match.
    private static let addTaskInputLead = "The fields of AddTaskInput are: "

    /// The selection of a task list field.
    private static let taskListSelection = "{ edges { node { id } } }"

    /// Each removed parameter, in each position where the agent writes it, with the text of its warning.
    static let cases: [RemovedParameterCase] = [
        addTaskCase(field: #"due: "2026-01-01""#, warning: "`due`" + noDateText),
        addTaskCase(field: #"scheduled: "2026-01-01""#, warning: "`scheduled`" + noDateText),
        addTaskCase(field: #"project: "web""#, warning: "`project` is removed, use tags. The call ignored it."),
        addTaskCase(
            field: #"attachments: ["a.png"]"#,
            warning: "`attachments` is removed, with no replacement. The call ignored it."
        ),
        tasksCase(
            arguments: "exclude_done: true",
            warning: "`exclude_done` is removed, use the filter `!#DONE`. The call ignored it."
        ),
        tasksCase(
            arguments: "excludeDone: true",
            warning: "`excludeDone` is removed, use the filter `!#DONE`. The call ignored it."
        ),
        tasksCase(
            arguments: "first: 1, page: 2",
            warning: "`page` is removed, use `first` and `after` (cursor paging). The call ignored it."
        ),
        tasksCase(
            arguments: #"detail: "full""#,
            warning: "`detail` is removed, choose the fields in the selection set. The call ignored it."
        ),
        tasksCase(
            arguments: "include_counts: true",
            warning: "`include_counts` is removed, select `summary` (or `totalCount`). The call ignored it."
        ),
        tasksCase(
            arguments: "INCLUDE_COUNTS: true",
            warning: "`INCLUDE_COUNTS` is removed, select `summary` (or `totalCount`). The call ignored it."
        ),
    ]

    /// The warning text of the removed `due` parameter.
    private static let dueWarning = "`due`" + noDateText

    /// Each removed parameter whose value is a variable. The removed `due` field of an `input` object: with no other
    /// use of the variable, with an other use in an argument, in a directive, or in a fragment that the operation
    /// spreads, and with a second variable. The removed `page` argument of a field, with no other use of the variable.
    static let variableCases: [RemovedVariableCase] = [
        dueVariableCase(
            document: #"mutation ($d: String) { addTask(input: { title: "x", due: $d }) { title } }"#,
            variables: ["d": "2026-01-01"],
            rewrittenText: #"mutation  { addTask(input: { title: "x",  }) { title } }"#
        ),
        dueVariableCase(
            document: "mutation ($t: String!) { addTask(input: { title: $t, due: $t }) { title } }",
            variables: ["t": "x"],
            rewrittenText: "mutation ($t: String!) { addTask(input: { title: $t,  }) { title } }"
        ),
        dueVariableCase(
            document: #"mutation ($d: Boolean!) { addTask(input: { title: "x", due: $d }) "#
                + "{ title @include(if: $d) } }",
            variables: ["d": true],
            rewrittenText: #"mutation ($d: Boolean!) { addTask(input: { title: "x",  }) "#
                + "{ title @include(if: $d) } }"
        ),
        dueVariableCase(
            document: #"mutation ($d: Boolean!) { addTask(input: { title: "x", due: $d }) { ...F } }"#
                + " fragment F on Task { title @include(if: $d) }",
            variables: ["d": true],
            rewrittenText: #"mutation ($d: Boolean!) { addTask(input: { title: "x",  }) { ...F } }"#
                + " fragment F on Task { title @include(if: $d) }"
        ),
        dueVariableCase(
            document: "mutation ($t: String!, $d: String) { addTask(input: { title: $t, due: $d }) { title } }",
            variables: ["t": "x", "d": "2026-01-01"],
            rewrittenText: "mutation ($t: String!, ) { addTask(input: { title: $t,  }) { title } }"
        ),
        dueVariableCase(
            document: "mutation ($d: String, $t: String!) { addTask(input: { title: $t, due: $d }) { title } }",
            variables: ["t": "x", "d": "2026-01-01"],
            rewrittenText: "mutation ($t: String!) { addTask(input: { title: $t,  }) { title } }"
        ),
        RemovedVariableCase(
            document: "query ($p: Int) { board { tasks(page: $p) { totalCount } } }",
            variables: ["p": 2],
            rewrittenText: "query  { board { tasks { totalCount } } }",
            resultKey: "board",
            warning: "`page` is removed, use `first` and `after` (cursor paging). The call ignored it."
        ),
    ]

    // MARK: - Helpers

    /// Gives the case of an `addTask` with one removed field in its `input` object.
    ///
    /// - Parameters:
    ///   - field: The removed field and its value.
    ///   - warning: The text of the warning.
    /// - Returns: The case.
    private static func addTaskCase(field: String, warning: String) -> RemovedParameterCase {
        RemovedParameterCase(
            document: #"mutation { addTask(input: { title: "x", \#(field) }) { id } }"#,
            resultKey: "addTask",
            warning: warning
        )
    }

    /// Gives the case of a root `tasks` field with some arguments. The rewrite moves the field into `board`.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the field, with one removed parameter.
    ///   - warning: The text of the warning.
    /// - Returns: The case.
    private static func tasksCase(arguments: String, warning: String) -> RemovedParameterCase {
        RemovedParameterCase(
            document: "{ tasks(\(arguments)) \(taskListSelection) }",
            resultKey: "tasks",
            warning: warning
        )
    }

    /// Gives the case of an `addTask` whose `input` object has the removed `due` field with a variable value.
    ///
    /// - Parameters:
    ///   - document: The document that gives a variable as the value of `due`.
    ///   - variables: The values of the variables of the document.
    ///   - rewrittenText: The text that the rewrite must make from the document.
    /// - Returns: The case.
    private static func dueVariableCase(
        document: String,
        variables: [String: Map],
        rewrittenText: String
    ) -> RemovedVariableCase {
        RemovedVariableCase(
            document: document,
            variables: variables,
            rewrittenText: rewrittenText,
            resultKey: "addTask",
            warning: dueWarning
        )
    }

    /// Runs a test body on the fixture board in a new temporary repo. The repo stays until the body ends.
    ///
    /// - Parameter body: The test body. It gets the engine.
    /// - Throws: An error when the fixture cannot be made, or the error of the body.
    private static func withFixture(_ body: (KanbanGraph) async throws -> Void) async throws {
        let directory = try TemporaryDirectory()
        let made = try ColumnActorTests.makeFixtureGraph(in: directory)
        try await body(made.graph)
        withExtendedLifetime(directory) {}
    }

    /// Gives the only error of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The error object.
    /// - Throws: An error when the response does not have exactly one error.
    private static func onlyError(of response: String) throws -> [String: Any] {
        let errors = try NameRewriteTests.errors(of: response)
        try #require(errors.count == 1, "\(response)")
        return errors[0]
    }

    /// Expects that a response has no error, and that its `data` gives an object at a key.
    ///
    /// - Parameters:
    ///   - resultKey: The key in `data` of the field that must give a value.
    ///   - response: The response JSON text.
    /// - Throws: An error when the response is not a JSON object.
    private static func expectResult(at resultKey: String, in response: String) throws {
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        #expect(try KanbanGraphTests.data(of: response)[resultKey] is [String: Any], "\(response)")
    }

    /// Expects that a response has one warning: the warning of a removed parameter, with its code.
    ///
    /// - Parameters:
    ///   - warning: The text of the warning.
    ///   - response: The response JSON text.
    /// - Throws: An error when the response has no warnings.
    private static func expectRemovedWarning(_ warning: String, in response: String) throws {
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.message) == [warning], "\(response)")
        #expect(warnings.map(\.code) == [warningCode], "\(response)")
    }

    /// Gives the canonical names of a position from introspection: the input fields of an `input` type, the fields
    /// of an object type, or the arguments of a field.
    ///
    /// - Parameters:
    ///   - type: The name of the type.
    ///   - field: The name of a field of the type for its arguments, or `nil` for the fields of the type.
    ///   - graph: The engine.
    /// - Returns: The names, in the order of introspection.
    private static func canonicalNames(
        of type: String,
        argumentsOf field: String? = nil,
        on graph: KanbanGraph
    ) async throws -> [String] {
        let query = #"{ __type(name: "\#(type)") { inputFields { name } fields { name args { name } } } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        let described = try KanbanGraphTests.object(named: "__type", in: response)
        guard let field else {
            let entries = (described["inputFields"] as? [[String: Any]]) ?? (described["fields"] as? [[String: Any]])
            return try #require(entries).compactMap { entry in entry["name"] as? String }
        }
        let fields = try #require(described["fields"] as? [[String: Any]])
        let found = try #require(fields.first { entry in entry["name"] as? String == field })
        return try #require(found["args"] as? [[String: Any]]).compactMap { entry in entry["name"] as? String }
    }

    /// Expects that a response has one validation error that names a written name and ends with the list of all the
    /// canonical names of the position. The list is in the order of the schema, and introspection can give a
    /// different order, so the test compares the names as a set.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - written: The name with no match, as the document wrote it.
    ///   - lead: The text before the names in the list, for example "The fields of AddTaskInput are: ".
    ///   - names: The canonical names of the position.
    /// - Throws: An error when the response does not have exactly one error, or the message has no list.
    private static func expectNoMatchError(
        in response: String,
        naming written: String,
        listing lead: String,
        of names: [String]
    ) throws {
        let error = try onlyError(of: response)
        let message = try #require(error["message"] as? String)
        #expect(message.contains("\"\(written)\""), "\(response)")
        #expect(ErrorCoverageTests.code(of: error) == "GRAPHQL_VALIDATION_FAILED")
        let listStart = try #require(message.range(of: " " + lead), "\(response)").upperBound
        let list = message[listStart...]
        #expect(list.hasSuffix("."), "\(response)")
        let listed = list.dropLast().components(separatedBy: ", ")
        #expect(listed.count == names.count, "\(response)")
        #expect(Set(listed) == Set(names), "\(response)")
    }

    // MARK: - Removed parameters

    @Test("A removed Rust parameter is ignored, and the response gives its warning", arguments: cases)
    func removedParameterGivesWarning(removed: RemovedParameterCase) async throws {
        try await Self.withFixture { graph in
            let response = try await KanbanGraphTests.execute(removed.document, on: graph)
            #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
            #expect(try KanbanGraphTests.data(of: response)[removed.resultKey] is [String: Any], "\(response)")
            let warnings = try ResponseWarningsTests.warnings(of: response)
            #expect(warnings.map(\.message) == [removed.warning], "\(response)")
            #expect(warnings.map(\.code) == [Self.warningCode], "\(response)")
        }
    }

    @Test("A removed Rust key in the value of a variable is ignored, and the response gives its warning")
    func removedVariableKeyGivesWarning() async throws {
        try await Self.withFixture { graph in
            let document = "mutation ($input: AddTaskInput!) { addTask(input: $input) { title } }"
            let input: Map = ["title": "x", "due": "2026-01-01"]
            let response = try await KanbanGraphTests.execute(document, variables: ["input": input], on: graph)
            let added = try KanbanGraphTests.object(named: "addTask", in: response)
            #expect(added["title"] as? String == "x", "\(response)")
            let warnings = try ResponseWarningsTests.warnings(of: response)
            #expect(warnings.map(\.message) == ["`due`" + Self.noDateText], "\(response)")
        }
    }

    // MARK: - Removed parameter with a variable value

    @Test("A removed Rust parameter whose value is a variable is ignored, and the response gives its warning",
          arguments: variableCases)
    func removedVariableValueGivesWarning(removed: RemovedVariableCase) async throws {
        try await Self.withFixture { graph in
            let variables = removed.variables
            let response = try await KanbanGraphTests.execute(removed.document, variables: variables, on: graph)
            try Self.expectResult(at: removed.resultKey, in: response)
            try Self.expectRemovedWarning(removed.warning, in: response)
        }
    }

    @Test("The rewrite takes out the definition of a variable that only a removed Rust parameter reads",
          arguments: variableCases)
    func removedVariableValueTakesOutUnusedDefinition(removed: RemovedVariableCase) throws {
        #expect(try NameRewriteTests.rewritten(from: removed.document).text == removed.rewrittenText)
    }

    @Test("A variable that the caller does not read, and that no removed Rust parameter reads, keeps its definition")
    func unreadVariableKeepsDefinition() throws {
        let document = #"mutation ($u: String) { addTask(input: { title: "x", due: "y" }) { title } }"#
        let text = #"mutation ($u: String) { addTask(input: { title: "x",  }) { title } }"#
        #expect(try NameRewriteTests.rewritten(from: document).text == text)
    }

    // MARK: - Failed calls

    /// Expects that the response of a failed call has one error with a code, and the one warning of the removed
    /// `due` parameter.
    ///
    /// - Parameters:
    ///   - code: The code of the error.
    ///   - response: The response JSON text.
    /// - Throws: An error when the response does not have exactly one error, or has no warnings.
    private static func expectFailure(coded code: String, withDueWarningIn response: String) throws {
        let error = try onlyError(of: response)
        #expect(ErrorCoverageTests.code(of: error) == code, "\(response)")
        try expectRemovedWarning(dueWarning, in: response)
    }

    @Test("A removed Rust parameter in a call whose field fails gives its warning, and the next call gives none")
    func removedParameterInFailedFieldGivesWarning() async throws {
        try await Self.withFixture { graph in
            let input = #"id: "\#(AddUpdateTaskTests.unknownTask)", \#(Self.removedDue)"#
            let update = "updateTask(input: { \(input) }) { id }"
            let failed = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: update), on: graph)
            try Self.expectFailure(coded: "NOT_FOUND", withDueWarningIn: failed)
            let next = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph)
            #expect(try UnreadableRelatedBoardTests.hasNoWarning(next), "\(next)")
        }
    }

    @Test("A removed Rust parameter in a BOARD_BUSY call gives its warning, and the next call gives none")
    func removedParameterInBusyCallGivesWarning() async throws {
        let (harness, clock) = try AgentPlanPostTests.makeHarnessWithOtherProcess()
        try await harness.addTask(titled: AgentPlanPostTests.firstTitle)
        clock.arm(.writingAtEachRead)
        let add = #"addTask(input: { title: "\#(AgentPlanPostTests.secondTitle)", \#(Self.removedDue) }) { id }"#
        let busy = try await harness.call(AddUpdateTaskTests.mutation(of: add))
        clock.arm(.idle)
        try Self.expectFailure(coded: "BOARD_BUSY", withDueWarningIn: busy)
        let next = try await harness.call(AgentPlanPostTests.addTask(titled: AgentPlanPostTests.secondTitle))
        #expect(try UnreadableRelatedBoardTests.hasNoWarning(next), "\(next)")
    }

    // MARK: - No match

    @Test("An input field with no match fails, and the error lists all the fields of AddTaskInput")
    func inputFieldWithNoMatchListsTheFields() async throws {
        try await Self.withFixture { graph in
            let names = try await Self.canonicalNames(of: "AddTaskInput", on: graph)
            let document = #"mutation { addTask(input: { title: "x", zzz: 1 }) { id } }"#
            let response = try await KanbanGraphTests.execute(document, on: graph)
            try Self.expectNoMatchError(in: response, naming: "zzz", listing: Self.addTaskInputLead, of: names)
        }
    }

    @Test("An argument with no match fails, and the error lists all the arguments of the field")
    func argumentWithNoMatchListsTheArguments() async throws {
        try await Self.withFixture { graph in
            let names = try await Self.canonicalNames(of: "Board", argumentsOf: "tasks", on: graph)
            let response = try await KanbanGraphTests.execute("{ board { tasks(zzz: 1) { totalCount } } }", on: graph)
            let lead = "The arguments of Board.tasks are: "
            try Self.expectNoMatchError(in: response, naming: "zzz", listing: lead, of: names)
        }
    }

    @Test("A selection field with no match fails, and the error lists all the fields of the type")
    func selectionFieldWithNoMatchListsTheFields() async throws {
        try await Self.withFixture { graph in
            let names = try await Self.canonicalNames(of: "Board", on: graph)
            let response = try await KanbanGraphTests.execute("{ board { zzz } }", on: graph)
            try Self.expectNoMatchError(in: response, naming: "zzz", listing: "The fields of Board are: ", of: names)
        }
    }

    @Test("A key with no match in the value of a variable fails, and the error lists all the fields of the type")
    func variableKeyWithNoMatchListsTheFields() async throws {
        try await Self.withFixture { graph in
            let names = try await Self.canonicalNames(of: "AddTaskInput", on: graph)
            let document = "mutation ($input: AddTaskInput!) { addTask(input: $input) { id } }"
            let input: Map = ["title": "x", "zzz": 1]
            let response = try await KanbanGraphTests.execute(document, variables: ["input": input], on: graph)
            try Self.expectNoMatchError(in: response, naming: "zzz", listing: Self.addTaskInputLead, of: names)
        }
    }
}
