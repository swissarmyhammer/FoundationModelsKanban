import Foundation
import FoundationModelsExtras
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

    /// The matches that the `AMBIGUOUS_ID` test gives for the prefix `01KT6SA`: a task with a title, and a comment,
    /// which has no title.
    static let ambiguousMatches = [
        KanbanError.AmbiguousMatch(id: "^jraj9vg", title: "Fix the build"),
        KanbanError.AmbiguousMatch(id: "^rc9rb4g", title: nil),
    ]

    /// The `INVALID_FILTER` error of the codes test and of the `FILTER_MODEL_MISSING` test.
    static let filterError = KanbanError.invalidFilter(
        filter: "#bug &&",
        position: filterFailureStart..<filterFailureEnd,
        detail: "an operand must follow &&",
        example: "#bug && @alice"
    )

    /// One error of each case, with the code that the case must give.
    static let codes: [(KanbanError, String)] = [
        (.notFound(type: .task, reference: "^zzzzzzz"), "NOT_FOUND"),
        (.ambiguousID(reference: "01KT6SA", matches: ambiguousMatches), "AMBIGUOUS_ID"),
        (.actorNotFound(reference: "alice"), "ACTOR_NOT_FOUND"),
        (.duplicateID(type: .column, id: "doing"), "DUPLICATE_ID"),
        (.columnNotEmpty(column: "doing", liveTaskCount: liveTaskCount), "COLUMN_NOT_EMPTY"),
        (.dependencyCycle(path: ["^aaaaaaa", "^bbbbbbb", "^aaaaaaa"]), "DEPENDENCY_CYCLE"),
        (.tagRenameCycle(path: ["bug", "defect", "bug"]), "TAG_RENAME_CYCLE"),
        (.nothingToUndo, "NOTHING_TO_UNDO"),
        (.undoConflict(transaction: "01KTXN0001", laterTransactions: ["01KTXN0002"]), "UNDO_CONFLICT"),
        (filterError, "INVALID_FILTER"),
        (.filterModelMissing(filterError: filterError), "FILTER_MODEL_MISSING"),
        (.invalidTagName(name: "!!!"), "INVALID_TAG_NAME"),
        (.invalidSlug(name: "---"), "INVALID_SLUG"),
        (.invalidOrdinal(ordinal: "zz!"), "INVALID_ORDINAL"),
        (.conflictingPlacement(fields: ["before", "after"]), "CONFLICTING_PLACEMENT"),
        (.staleWrite(task: "^aaaaaaa", givenVersion: staleVersion, currentVersion: currentVersion), "STALE_WRITE"),
        (.emptyComment, "EMPTY_COMMENT"),
        (.noPreviousColumn(task: "^aaaaaaa", column: firstColumn), "NO_PREVIOUS_COLUMN"),
        (.boardBusy(attempts: commitAttempts), "BOARD_BUSY"),
        (.incompatibleBoard(directory: rustBoardPath), "INCOMPATIBLE_BOARD"),
    ]

    /// The old version of the task in the `STALE_WRITE` tests: the version that the caller read.
    static let staleVersion = "01KTXN0001AAAAAAAAAAAAAAAA"

    /// The current version of the task in the `STALE_WRITE` tests.
    static let currentVersion = "01KTXN0002BBBBBBBBBBBBBBBB"

    /// The slug of the first column in the `NO_PREVIOUS_COLUMN` tests.
    static let firstColumn = "todo"

    /// The task refs that name no task, in the test of `NOT_FOUND` for a list of ids.
    static let missingTaskRefs = ["^zzzzzzz", "^yyyyyyy"]

    /// The path of a `.kanban/` directory of the old Rust kanban, in the `INCOMPATIBLE_BOARD` tests.
    static let rustBoardPath = "/tmp/rust-repo/.kanban"

    /// The errors of the reserved slugs: the slug `board`, and the names of the virtual tags. Each has the code of the
    /// slug rule of its node type. These cases share the codes of ``codes``, so the test of distinct codes does not
    /// read them.
    static let reservedSlugCodes: [(KanbanError, String)] = [
        (.reservedSlug(type: .column), "INVALID_SLUG"),
        (.reservedSlug(type: .actor), "INVALID_SLUG"),
        (.reservedTagName, "INVALID_TAG_NAME"),
        (.virtualTagName(tag: .done), "INVALID_TAG_NAME"),
    ]

    // MARK: - Codes

    @Test("Each case gives its exact code", arguments: codes + reservedSlugCodes)
    func caseGivesItsCode(error: KanbanError, expectedCode: String) {
        #expect(error.code == expectedCode)
    }

    @Test("The cases give twenty different codes")
    func codesAreDistinct() {
        #expect(Set(Self.codes.map { $0.0.code }).count == Self.codes.count)
    }

    // MARK: - Messages

    @Test("INCOMPATIBLE_BOARD names the .kanban/ directory, and tells the caller to remove it")
    func incompatibleBoardMessage() {
        #expect(
            KanbanError.incompatibleBoard(directory: Self.rustBoardPath).message
                == "There is an incompatible board at `/tmp/rust-repo/.kanban`. Remove it, then try again."
        )
    }

    // MARK: - Call failure

    @Test("A call failure gives the KanbanError itself, and INCOMPATIBLE_BOARD for an incompatible event log")
    func callFailureGivesCorrectableError() {
        #expect(KanbanError(callFailure: KanbanError.nothingToUndo) == .nothingToUndo)
        #expect(
            KanbanError(callFailure: EventLogError.incompatibleBoard(directory: Self.rustBoardPath))
                == .incompatibleBoard(directory: Self.rustBoardPath)
        )
    }

    @Test("A call failure that the caller cannot correct gives no KanbanError")
    func callFailureKeepsIOFault() {
        let fault = EventLogError.fileSystem(path: Self.rustBoardPath, detail: "denied")
        #expect(KanbanError(callFailure: fault) == nil)
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

    @Test("NOT_FOUND for a list of ids has the code NOT_FOUND, names each reference, and tells that nothing changed")
    func nodesNotFoundMessage() {
        let error = KanbanError.nodesNotFound(type: .task, references: Self.missingTaskRefs)
        #expect(error.code == "NOT_FOUND")
        #expect(
            error.message
                == "No task has the references \"^zzzzzzz\", \"^yyyyyyy\", so the call wrote nothing. Query the board "
                + "to get the correct ids, and then send the call again."
        )
    }

    @Test("NOT_FOUND for a board has the code NOT_FOUND, names the reference, and lists the search roots")
    func boardNotFoundMessage() {
        let error = KanbanError.boardNotFound(reference: "github.com/o/missing", searchRoots: ["/src", "/work"])
        #expect(error.code == "NOT_FOUND")
        #expect(
            error.message
                == "No board has the reference \"github.com/o/missing\". The scan looked for git repos and for "
                + "folders with a .kanban/ folder in: /src, /work. Use a board key, a board ID, a folder name, or a "
                + "path from these places, and then send the call again."
        )
    }

    @Test("NOT_FOUND for a board of a transaction names the board key and tells how to name a copy by its path")
    func transactionBoardNotLoadedMessage() {
        let error = KanbanError.transactionBoardNotLoaded(transaction: "01KTXN0001", board: "github.com/o/lib")
        #expect(error.code == "NOT_FOUND")
        #expect(
            error.message
                == "Transaction \"01KTXN0001\" also changed the board \"github.com/o/lib\", and no loaded copy of "
                + "that board has its changes, so the call wrote nothing on any board. Name the copy by its path, "
                + "for example undoChange(input: { txn: \"01KTXN0001\", boards: [\"/path/to/copy\"] }), and then "
                + "send the call again."
        )
    }

    @Test("AMBIGUOUS_ID gives the id and the title of each match, and the id alone for a match with no title")
    func ambiguousIDMessage() {
        let error = KanbanError.ambiguousID(reference: "01KT6SA", matches: Self.ambiguousMatches)
        #expect(
            error.message
                == "The reference \"01KT6SA\" matches more than one id: ^jraj9vg \"Fix the build\", ^rc9rb4g. "
                + "Send one of these ids."
        )
    }

    @Test("AMBIGUOUS_ID gives a full id as the caller sends it, and leaves out an empty title")
    func ambiguousIDMessageWithFullIDs() {
        let matches = [
            KanbanError.AmbiguousMatch(id: ShortIDTests.ownerOf0123456, title: "Merge the branch"),
            KanbanError.AmbiguousMatch(id: ShortIDTests.secondOwnerOf0123456, title: ""),
        ]
        let error = KanbanError.ambiguousID(reference: "01KT6", matches: matches)
        #expect(
            error.message
                == "The reference \"01KT6\" matches more than one id: 01KT6R6HR3KJT6JVNDR0123456 \"Merge the branch\", "
                + "01KT6SAMJAJ40XVQ9YJ0123456. Send one of these ids."
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
                + "and then send undoChange(input: { txn: <id> })."
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
                + "or send undoChange(input: { txn: \"01KTXN0001\", force: true }) to write the inverse anyway."
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

    @Test("INVALID_SLUG for the slug board tells that the board URI reserves the slug")
    func reservedSlugMessage() {
        #expect(
            KanbanError.reservedSlug(type: .column).message
                == "The slug \"board\" is reserved for the board URI kanban://<board-key>/board, so a column cannot "
                + "have it. Use a name or an id that gives a different slug."
        )
    }

    @Test("INVALID_TAG_NAME for the slug board tells that the board URI reserves the slug")
    func reservedTagNameMessage() {
        #expect(
            KanbanError.reservedTagName.message
                == "The slug \"board\" is reserved for the board URI kanban://<board-key>/board, so a tag cannot "
                + "have it. Use a tag name that gives a different slug."
        )
    }

    @Test("INVALID_TAG_NAME for the name of a virtual tag names the virtual tag")
    func virtualTagNameMessage() {
        #expect(
            KanbanError.virtualTagName(tag: .deleted).message
                == "The slug \"deleted\" is the name of the virtual tag DELETED, and the filter #DELETED matches only "
                + "the virtual tag, so a tag cannot have it. Use a tag name that gives a different slug."
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

    @Test("STALE_WRITE names the task and both versions, and tells the caller to read the task again")
    func staleWriteMessage() {
        let error = KanbanError.staleWrite(
            task: "^aaaaaaa",
            givenVersion: Self.staleVersion,
            currentVersion: Self.currentVersion
        )
        #expect(
            error.message
                == "The task \"^aaaaaaa\" changed after the version \"01KTXN0001AAAAAAAAAAAAAAAA\": its current version "
                + "is \"01KTXN0002BBBBBBBBBBBBBBBB\", so the call wrote nothing. Read the task again, and then send the "
                + "call again with ifVersion: \"01KTXN0002BBBBBBBBBBBBBBBB\", or with no ifVersion to write over the "
                + "change."
        )
    }

    @Test("EMPTY_COMMENT tells that nothing changed, and asks for a comment that tells why the task goes back")
    func emptyCommentMessage() {
        #expect(
            KanbanError.emptyComment.message
                == "The comment is empty, so the call wrote nothing. Give a comment that tells why the task goes back, "
                + "and then send the call again."
        )
    }

    @Test("NO_PREVIOUS_COLUMN names the task and the first column, and asks for the column")
    func noPreviousColumnMessage() {
        #expect(
            KanbanError.noPreviousColumn(task: "^aaaaaaa", column: Self.firstColumn).message
                == "The task \"^aaaaaaa\" is in the first column \"todo\", so no column comes before it, and the call "
                + "wrote nothing. Give the column of the task, and then send the call again."
        )
    }

    @Test("FILTER_MODEL_MISSING tells that the engine has no filter model, and gives the INVALID_FILTER message")
    func filterModelMissingMessage() {
        #expect(
            KanbanError.filterModelMissing(filterError: Self.filterError).message
                == "The engine has no filter model, so it cannot write a filter from English text. Send the text in "
                + "the filter language. The filter \"#bug &&\" is not valid at 5..7: an operand must follow &&. "
                + "Correct the filter, for example: #bug && @alice"
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

    @Test("UNREACHABLE_BOARD names the board ref and tells the caller to leave it out, with no word on the board")
    func unreachableBoardMessage() {
        let error = KanbanError.unreachableBoard(reference: CrossRepoReadTests.missingKey)
        #expect(error.code == ViewerReachTests.unreachableCode)
        #expect(
            error.message
                == "This client reaches only the board of the folder of its session, so the call cannot name the board "
                + "\"\(CrossRepoReadTests.missingKey)\". Leave out the board ref, or name the board of that folder, and "
                + "then send the call again."
        )
    }

    @Test("UNREACHABLE_BOARD for a field that reaches other boards names the field and tells the caller to leave it out")
    func unreachableBoardsMessage() {
        let error = KanbanError.unreachableBoards(field: BoardStore.boardsField)
        #expect(error.code == ViewerReachTests.unreachableCode)
        #expect(
            error.message
                == "This client reaches only the board of the folder of its session, so the call cannot use boards, "
                + "which reaches other boards. Leave out the board ref, or name the board of that folder, and then send "
                + "the call again."
        )
    }

    @Test("SUBSCRIPTION_NOT_IN_TOOL with the kanban hint tells the agent to use the history")
    func subscriptionNotInToolMessage() {
        #expect(
            GraphQLToolkitError.subscriptionNotInTool(hint: KanbanTool.subscriptionHint).message
                == "The tool does not run a subscription. Use board { history(since: <txn>) } "
                + "to get the changes after a known transaction."
        )
    }

    // MARK: - GraphQL error JSON

    @Test("The JSON form has message, path, and extensions.code")
    func responseErrorJSON() throws {
        let error = KanbanError.notFound(type: .task, reference: "^zzzzzzz")
        let path: [CodedErrorJSON.PathComponent] = [.key("addTask"), .key("tasks"), .index(Self.pathIndex)]
        let object = try Self.jsonObject(of: CodedErrorJSON(error, at: path))
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
        let object = try Self.jsonObject(of: CodedErrorJSON(KanbanError.nothingToUndo))
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
        let original = CodedErrorJSON(KanbanError.nothingToUndo, at: [.key("undoChange"), .index(0)])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(CodedErrorJSON.self, from: data) == original)
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
