import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the error catalog (plan.md §4.4): the code of each case, the corrective message of each case, and the
/// GraphQL error JSON.
@Suite("Kanban errors")
struct KanbanErrorTests {
    /// The number of live tasks in the column of the `COLUMN_NOT_EMPTY` test.
    static let liveTaskCount = 3

    /// The number of commit attempts in the `BOARD_BUSY` test.
    static let commitAttempts = 5

    /// The start of the failure position in the `INVALID_FILTER` test.
    static let filterFailureStart = 5

    /// The end of the failure position in the `INVALID_FILTER` test.
    static let filterFailureEnd = 7

    /// The index in the response path of the JSON test.
    static let pathIndex = 2

    /// The short ids that the `AMBIGUOUS_ID` test gives: the short ids of two ULIDs with the prefix `01KT6SA`.
    static let ambiguousMatches = [
        ShortID(ofULIDString: "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"),
        ShortID(ofULIDString: "01KT6SA4911JQPK09YQRC9RB4G"),
    ]

    /// One error of each case, with the code that the case must give.
    static let codes: [(KanbanError, String)] = [
        (.invalidVariables(received: "a number"), "INVALID_VARIABLES"),
        (.notFound(type: .task, reference: "^zzzzzzz"), "NOT_FOUND"),
        (.ambiguousID(reference: "01KT6SA", matches: ambiguousMatches), "AMBIGUOUS_ID"),
        (.actorNotFound(reference: "alice"), "ACTOR_NOT_FOUND"),
        (.duplicateID(type: .column, id: "doing"), "DUPLICATE_ID"),
        (.columnNotEmpty(column: "doing", liveTaskCount: liveTaskCount), "COLUMN_NOT_EMPTY"),
        (.dependencyCycle(path: ["^aaaaaaa", "^bbbbbbb", "^aaaaaaa"]), "DEPENDENCY_CYCLE"),
        (.tagRenameCycle(path: ["bug", "defect", "bug"]), "TAG_RENAME_CYCLE"),
        (.nothingToUndo, "NOTHING_TO_UNDO"),
        (.undoConflict(transaction: "01KTXN0001", laterTransactions: ["01KTXN0002"]), "UNDO_CONFLICT"),
        (
            .invalidFilter(
                filter: "#bug &&",
                position: filterFailureStart..<filterFailureEnd,
                detail: "an operand must follow &&",
                example: "#bug && @alice"
            ),
            "INVALID_FILTER"
        ),
        (.invalidTagName(name: "!!!"), "INVALID_TAG_NAME"),
        (.invalidSlug(name: "---"), "INVALID_SLUG"),
        (.invalidOrdinal(ordinal: "zz!"), "INVALID_ORDINAL"),
        (.boardBusy(attempts: commitAttempts), "BOARD_BUSY"),
        (.subscriptionNotInTool, "SUBSCRIPTION_NOT_IN_TOOL"),
    ]

    // MARK: - Codes

    @Test("Each case gives its exact code", arguments: codes)
    func caseGivesItsCode(error: KanbanError, expectedCode: String) {
        #expect(error.code == expectedCode)
    }

    @Test("The cases give sixteen different codes")
    func codesAreDistinct() {
        #expect(Set(Self.codes.map { $0.0.code }).count == Self.codes.count)
    }

    // MARK: - Messages

    @Test("INVALID_VARIABLES tells the two correct forms of the variables")
    func invalidVariablesMessage() {
        let error = KanbanError.invalidVariables(received: "a number")
        #expect(
            error.message
                == "The variables are not a JSON object. The call sent a number. Send the variables as a JSON object, "
                + "or as a string that holds a JSON object, for example {\"id\": \"^ajv8v4t\"}."
        )
    }

    @Test("NOT_FOUND names the node type and the reference")
    func notFoundMessage() {
        let error = KanbanError.notFound(type: .task, reference: "^zzzzzzz")
        #expect(
            error.message
                == "No task has the reference \"^zzzzzzz\". Query the board to get the correct ids, "
                + "and then send the call again."
        )
    }

    @Test("NOT_FOUND for a board has the code NOT_FOUND, names the reference, and lists the search roots")
    func boardNotFoundMessage() {
        let error = KanbanError.boardNotFound(reference: "github.com/o/missing", searchRoots: ["/src", "/work"])
        #expect(error.code == "NOT_FOUND")
        #expect(
            error.message
                == "No board has the reference \"github.com/o/missing\". The scan looked for git repos in: /src, "
                + "/work. Use a board key, a repo directory name, or a repo path from these places, "
                + "and then send the call again."
        )
    }

    @Test("AMBIGUOUS_ID gives the matching short ids")
    func ambiguousIDMessage() {
        let error = KanbanError.ambiguousID(reference: "01KT6SA", matches: Self.ambiguousMatches)
        #expect(
            error.message
                == "The reference \"01KT6SA\" matches more than one id: ^jraj9vg, ^rc9rb4g. "
                + "Send one of these short ids."
        )
    }

    @Test("ACTOR_NOT_FOUND tells how to add the actor")
    func actorNotFoundMessage() {
        let error = KanbanError.actorNotFound(reference: "alice")
        #expect(
            error.message
                == "No actor has the reference \"alice\". Add the actor with addActor, "
                + "or use the id of an actor of the board."
        )
    }

    @Test("DUPLICATE_ID names the node type and the id")
    func duplicateIDMessage() {
        let error = KanbanError.duplicateID(type: .column, id: "doing")
        #expect(
            error.message
                == "The board already has the column with the id \"doing\". Use a different id, "
                + "or update that column."
        )
    }

    @Test("COLUMN_NOT_EMPTY gives the number of live tasks")
    func columnNotEmptyMessage() {
        let error = KanbanError.columnNotEmpty(column: "doing", liveTaskCount: Self.liveTaskCount)
        #expect(
            error.message
                == "The column \"doing\" has 3 live tasks. Move or delete these tasks, "
                + "and then delete the column again."
        )
    }

    @Test("DEPENDENCY_CYCLE gives the cycle path")
    func dependencyCycleMessage() {
        let error = KanbanError.dependencyCycle(path: ["^aaaaaaa", "^bbbbbbb", "^aaaaaaa"])
        #expect(
            error.message
                == "The dependency makes a cycle: ^aaaaaaa -> ^bbbbbbb -> ^aaaaaaa. "
                + "Remove one dependency of the cycle."
        )
    }

    @Test("TAG_RENAME_CYCLE gives the rename chain")
    func tagRenameCycleMessage() {
        let error = KanbanError.tagRenameCycle(path: ["bug", "defect", "bug"])
        #expect(
            error.message
                == "The tag rename makes a cycle: bug -> defect -> bug. "
                + "Rename the tag to a name that is not in the cycle."
        )
    }

    @Test("NOTHING_TO_UNDO tells how to find a transaction")
    func nothingToUndoMessage() {
        #expect(
            KanbanError.nothingToUndo.message
                == "There is no transaction to undo. Use board { history } to find the id of a transaction, "
                + "and then send undo(txn: <id>)."
        )
    }

    @Test("UNDO_CONFLICT gives the later transactions and the force option")
    func undoConflictMessage() {
        let error = KanbanError.undoConflict(
            transaction: "01KTXN0001",
            laterTransactions: ["01KTXN0002", "01KTXN0003"]
        )
        #expect(
            error.message
                == "Later transactions changed the same properties as transaction \"01KTXN0001\": "
                + "01KTXN0002, 01KTXN0003. Undo these transactions first, "
                + "or send undo(txn: \"01KTXN0001\", force: true) to write the inverse anyway."
        )
    }

    @Test("INVALID_FILTER gives the position, the detail, and an example")
    func invalidFilterMessage() {
        let error = KanbanError.invalidFilter(
            filter: "#bug &&",
            position: Self.filterFailureStart..<Self.filterFailureEnd,
            detail: "an operand must follow &&",
            example: "#bug && @alice"
        )
        #expect(
            error.message
                == "The filter \"#bug &&\" is not valid at 5..7: an operand must follow &&. "
                + "Correct the filter, for example: #bug && @alice"
        )
    }

    @Test("INVALID_TAG_NAME tells what a tag name must hold")
    func invalidTagNameMessage() {
        #expect(
            KanbanError.invalidTagName(name: "!!!").message
                == "The tag name \"!!!\" gives an empty slug. Use a name that has one or more letters or digits."
        )
    }

    @Test("INVALID_SLUG tells what a name must hold")
    func invalidSlugMessage() {
        #expect(
            KanbanError.invalidSlug(name: "---").message
                == "The name \"---\" gives an empty slug. Use a name that has one or more letters or digits."
        )
    }

    @Test("INVALID_ORDINAL tells the other ways to place a task")
    func invalidOrdinalMessage() {
        #expect(
            KanbanError.invalidOrdinal(ordinal: "zz!").message
                == "The ordinal \"zz!\" is not a valid fractional index. Use before or after with a neighbor task, "
                + "or leave out the ordinal to put the task at the end of the column."
        )
    }

    @Test("BOARD_BUSY tells the caller to send the call again")
    func boardBusyMessage() {
        #expect(
            KanbanError.boardBusy(attempts: Self.commitAttempts).message
                == "The board changed during each of the 5 commit attempts, so the call wrote nothing. "
                + "Send the call again."
        )
    }

    @Test("SUBSCRIPTION_NOT_IN_TOOL tells the agent to use the history")
    func subscriptionNotInToolMessage() {
        #expect(
            KanbanError.subscriptionNotInTool.message
                == "The tool does not run a subscription. Use board { history(since: <txn>) } "
                + "to get the changes after a known transaction."
        )
    }

    // MARK: - GraphQL error JSON

    @Test("The JSON form has message, path, and extensions.code")
    func responseErrorJSON() throws {
        let error = KanbanError.notFound(type: .task, reference: "^zzzzzzz")
        let path: [KanbanError.PathComponent] = [.key("addTask"), .key("tasks"), .index(Self.pathIndex)]
        let object = try Self.jsonObject(of: error.responseError(at: path))
        #expect(object["message"] as? String == error.message)
        let decodedPath = try #require(object["path"] as? [Any])
        #expect(decodedPath.count == path.count)
        #expect(decodedPath.first as? String == "addTask")
        #expect(decodedPath.last as? Int == Self.pathIndex)
        let extensions = try #require(object["extensions"] as? [String: Any])
        #expect(extensions["code"] as? String == "NOT_FOUND")
    }

    @Test("An error with no field has an empty path")
    func responseErrorWithoutPath() throws {
        let object = try Self.jsonObject(of: KanbanError.subscriptionNotInTool.responseError())
        let decodedPath = try #require(object["path"] as? [Any])
        #expect(decodedPath.isEmpty)
    }

    @Test("The response of a call that fails has the error JSON in errors and no data")
    func responseJSONHasOnlyErrors() throws {
        let error = KanbanError.boardBusy(attempts: Self.commitAttempts)
        let object = #"{"extensions":{"code":"BOARD_BUSY"},"message":"\#(error.message)","path":[]}"#
        #expect(try error.responseJSON() == #"{"errors":[\#(object)]}"#)
    }

    @Test("The JSON form decodes to the same value")
    func responseErrorRoundTrip() throws {
        let original = KanbanError.nothingToUndo.responseError(at: [.key("undo"), .index(0)])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(KanbanError.ResponseError.self, from: data) == original)
    }

    /// Encodes a value, for example a response error, and reads the JSON back as an object.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON object.
    /// - Throws: An error when the encode fails or the JSON is not an object.
    static func jsonObject(of value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
