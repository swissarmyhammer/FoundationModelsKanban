import FoundationModelsExtras
import GraphQL

/// An error of the kanban schema that the tool returns to the caller in the `errors` list of a GraphQL response
/// (plan.md §4.4).
///
/// Each case has one fixed ``code`` and a ``message`` that tells the caller how to correct the call. Each case
/// holds the data that its message needs, for example the matching ids and titles of an ambiguous ULID prefix. The
/// errors that each endpoint can give, whatever its schema, are the ``GraphQLToolkitError`` of the toolkit, for
/// example `GRAPHQL_PARSE_FAILED` and `SUBSCRIPTION_NOT_IN_TOOL`. Both types are a ``CodedError``, so the toolkit
/// codes them the same way.
enum KanbanError: CodedError, Hashable {
    /// `NOT_FOUND`: no node of the type has the reference.
    case notFound(type: PatchNodeType, reference: String)

    /// `NOT_FOUND`: two or more refs of the list of a list mutation name no node of the type, so the call wrote
    /// nothing (divergence.md §20). The references are these refs as the call wrote them, in the order of the list.
    case nodesNotFound(type: PatchNodeType, references: [String])

    /// `NOT_FOUND`: the scan finds no board for the board ref (plan.md §6.6). The search roots are the places that
    /// the scan looked in, in scan order.
    case boardNotFound(reference: String, searchRoots: [String])

    /// `NOT_FOUND`: `undoChange` or `redoChange` of a transaction cannot reach a board that the transaction changed: no
    /// loaded copy of the board has the events of the transaction (plan.md §6.5, many boards; divergence.md X5, S8).
    /// The call writes nothing on any board. The transaction is its ULID, and the board is the key of that board.
    case transactionBoardNotLoaded(transaction: String, board: String)

    /// `INCOMPATIBLE_BOARD`: a `.kanban/` directory has a file or a directory of the old Rust kanban, so the engine
    /// does not read it, write to it, or make a new board in it (divergence.md Q6). The directory is the path of that
    /// `.kanban/` directory.
    case incompatibleBoard(directory: String)

    /// `AMBIGUOUS_ID`: the reference is a ULID prefix of more than one id (divergence.md P5). Each match gives the id
    /// that names it alone and its title, so that the next call can send one of these ids. A 7-character short id
    /// that more than one id has is not this error: it names the first match (divergence.md Q20).
    case ambiguousID(reference: String, matches: [AmbiguousMatch])

    /// `ACTOR_NOT_FOUND`: no actor has the reference.
    case actorNotFound(reference: String)

    /// `DUPLICATE_ID`: the board already has a node of the type with the id.
    case duplicateID(type: PatchNodeType, id: String)

    /// `COLUMN_NOT_EMPTY`: the column has live tasks, so the call cannot delete it.
    case columnNotEmpty(column: String, liveTaskCount: Int)

    /// `DEPENDENCY_CYCLE`: a `dependsOn` edge makes a cycle. The path goes from a task along the cycle and back to
    /// the same task.
    case dependencyCycle(path: [String])

    /// `TAG_RENAME_CYCLE`: a tag rename makes a cycle. The path goes from a tag name along the renames and back to
    /// the same name.
    case tagRenameCycle(path: [String])

    /// `NOTHING_TO_UNDO`: the board has no transaction to undo.
    case nothingToUndo

    /// `UNDO_CONFLICT`: later transactions changed the same properties as the transaction to undo.
    case undoConflict(transaction: String, laterTransactions: [String])

    /// `INVALID_FILTER`: the filter does not parse. The position is the range of characters where the parse
    /// failed, the detail tells the problem, and the example is one correct filter. The position counts Swift
    /// `Character`s from the start of the filter, and its end is exclusive. The error also gives it in
    /// `extensions.start` and `extensions.end` (``extensionFields``).
    case invalidFilter(filter: String, position: Range<Int>, detail: String, example: String)

    /// `FILTER_MODEL_MISSING`: the text of `translateFilter` is not a filter of the board, and the engine has no filter
    /// model to write a filter from it (divergence.md §17). The filter error is the `INVALID_FILTER` error of the text:
    /// the parse error, or the first name that names nothing. The error gives the span of the filter error in
    /// `extensions.start` and `extensions.end` (``extensionFields``).
    indirect case filterModelMissing(filterError: KanbanError)

    /// `FILTER_AGENT_FAILED`: the filter agent stopped before it wrote a filter, for example because the filter model
    /// is not available (divergence.md §17, "The loop"). The error counts no attempt. The reason is the text of the
    /// error that stopped the agent.
    case filterAgentFailed(reason: String)

    /// `INVALID_TAG_NAME`: the tag name gives an empty slug.
    case invalidTagName(name: String)

    /// `INVALID_TAG_NAME`: the tag name gives the slug ``Slug/reservedForBoard``, which the board URI reserves
    /// (plan.md §3.2).
    case reservedTagName

    /// `INVALID_TAG_NAME`: the tag name gives a slug that is the name of a virtual tag, in lowercase (plan.md §6). The
    /// filter atom of that name matches only the virtual tag, so a real tag with this slug is not useful. The tag is
    /// the virtual tag that the slug names.
    case virtualTagName(tag: VirtualTag)

    /// `INVALID_SLUG`: the name of a column or an actor gives an empty slug.
    case invalidSlug(name: String)

    /// `INVALID_SLUG`: the name or the id of a column or an actor gives the slug ``Slug/reservedForBoard``, which the
    /// board URI reserves (plan.md §3.2). The type is the node type of the node.
    case reservedSlug(type: PatchNodeType)

    /// `INVALID_ORDINAL`: the ordinal is not a valid fractional index.
    case invalidOrdinal(ordinal: String)

    /// `CONFLICTING_PLACEMENT`: the input of a move gives more than one place field. The fields are the names of
    /// these place fields, in the order of the input type.
    case conflictingPlacement(fields: [String])

    /// `STALE_WRITE`: the `ifVersion` of an `updateTask` call is not the current version of the task, so a different
    /// change came first, and the call wrote nothing (divergence.md §18). The task is the task ref as the call wrote
    /// it, the given version is the `ifVersion` as the call wrote it, and the current version is the ULID of the last
    /// event of the task.
    case staleWrite(task: String, givenVersion: String, currentVersion: String)

    /// `EMPTY_COMMENT`: the comment of a `rejectTask` call is empty or holds only white space, so the call wrote
    /// nothing (divergence.md §21).
    case emptyComment

    /// `NO_PREVIOUS_COLUMN`: a `rejectTask` call names no column, and the task shows in the first column, so no column
    /// comes before it, and the call wrote nothing (divergence.md §21). The task is the task ref as the call wrote it,
    /// and the column is the slug of the first column.
    case noPreviousColumn(task: String, column: String)

    /// `BOARD_BUSY`: the log of the board changed during each commit attempt (plan.md §5.4).
    case boardBusy(attempts: Int)

    /// `UNREACHABLE_BOARD`: a client that reaches only the board of the folder of the call named a different board
    /// (``BoardReach/ownBoard``; EXTRAS-9 rule 4). The reference is the board ref as the call wrote it. The call gives
    /// this error before it looks for the board, so the error is the same for a board that exists and for a board
    /// that does not.
    case unreachableBoard(reference: String)

    /// `UNREACHABLE_BOARD`: a client that reaches only the board of the folder of the call used a field that reads or
    /// changes other boards, for example `boards` or `collectBoards` (``BoardReach/ownBoard``; EXTRAS-9 rule 4). The
    /// field is the name of that field or argument.
    case unreachableBoards(field: String)
}

// MARK: - Code and message

extension KanbanError {
    /// The text between two items of a list in a message.
    static let listSeparator = ", "

    /// The text between two steps of a cycle path in a message.
    static let pathSeparator = " -> "

    /// The correction for a name that gives an empty slug.
    static let emptySlugCorrection = "Use a name that has one or more letters or digits."

    /// The correction for a tag name whose slug no tag can have.
    static let tagNameCorrection = "Use a tag name that gives a different slug."

    /// The code of the error, as `extensions.code` gives it, for example `NOT_FOUND`.
    var code: String {
        switch self {
        case .notFound, .nodesNotFound, .boardNotFound, .transactionBoardNotLoaded: "NOT_FOUND"
        case .incompatibleBoard: "INCOMPATIBLE_BOARD"
        case .ambiguousID: "AMBIGUOUS_ID"
        case .actorNotFound: "ACTOR_NOT_FOUND"
        case .duplicateID: "DUPLICATE_ID"
        case .columnNotEmpty: "COLUMN_NOT_EMPTY"
        case .dependencyCycle: "DEPENDENCY_CYCLE"
        case .tagRenameCycle: "TAG_RENAME_CYCLE"
        case .nothingToUndo: "NOTHING_TO_UNDO"
        case .undoConflict: "UNDO_CONFLICT"
        case .invalidFilter: "INVALID_FILTER"
        case .filterModelMissing: "FILTER_MODEL_MISSING"
        case .filterAgentFailed: "FILTER_AGENT_FAILED"
        case .invalidTagName, .reservedTagName, .virtualTagName: "INVALID_TAG_NAME"
        case .invalidSlug, .reservedSlug: "INVALID_SLUG"
        case .invalidOrdinal: "INVALID_ORDINAL"
        case .conflictingPlacement: "CONFLICTING_PLACEMENT"
        case .staleWrite: "STALE_WRITE"
        case .emptyComment: "EMPTY_COMMENT"
        case .noPreviousColumn: "NO_PREVIOUS_COLUMN"
        case .boardBusy: "BOARD_BUSY"
        case .unreachableBoard, .unreachableBoards: "UNREACHABLE_BOARD"
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .notFound(let type, let reference):
            "No \(Self.noun(for: type)) has the reference \"\(reference)\". Query the board to get the correct ids, "
                + "and then send the call again."
        case .nodesNotFound(let type, let references):
            "No \(Self.noun(for: type)) has the references "
                + "\(references.map { reference in "\"\(reference)\"" }.joined(separator: Self.listSeparator)), so the "
                + "call wrote nothing. Query the board to get the correct ids, and then send the call again."
        case .boardNotFound(let reference, let searchRoots):
            "No board has the reference \"\(reference)\". The scan looked for git repos and for folders with a "
                + ".kanban/ folder in: \(searchRoots.joined(separator: Self.listSeparator)). Use a board key, a board "
                + "ID, a folder name, or a path from these places, and then send the call again."
        case .transactionBoardNotLoaded(let transaction, let board):
            "Transaction \"\(transaction)\" also changed the board \"\(board)\", and no loaded copy of that board has "
                + "its changes, so the call wrote nothing on any board. Name the copy by its path, for example "
                + "\(MutationName.undoChange)(input: { txn: \"\(transaction)\", boards: [\"/path/to/copy\"] }), and "
                + "then send the call again."
        case .incompatibleBoard(let directory):
            "There is an incompatible board at `\(directory)`. Remove it, then try again."
        case .ambiguousID(let reference, let matches):
            "The reference \"\(reference)\" matches more than one id: "
                + "\(matches.map(\.text).joined(separator: Self.listSeparator)). Send one of these ids."
        case .actorNotFound(let reference):
            "No actor has the reference \"\(reference)\". Add the actor with addActor, "
                + "or use the id of an actor of the board."
        case .duplicateID(let type, let id):
            "The board already has the \(Self.noun(for: type)) with the id \"\(id)\". Use a different id, "
                + "or update that \(Self.noun(for: type))."
        case .columnNotEmpty(let column, let liveTaskCount):
            "The column \"\(column)\" has \(liveTaskCount) live tasks. Move or delete these tasks, "
                + "and then delete the column again."
        case .dependencyCycle(let path):
            "The dependency makes a cycle: \(path.joined(separator: Self.pathSeparator)). "
                + "Remove one dependency of the cycle."
        case .tagRenameCycle(let path):
            "The tag rename makes a cycle: \(path.joined(separator: Self.pathSeparator)). "
                + "Rename the tag to a name that is not in the cycle."
        case .nothingToUndo:
            "There is no transaction to undo. Use board { history } to find the id of a transaction, "
                + "and then send \(MutationName.undoChange)(input: { txn: <id> })."
        case .undoConflict(let transaction, let laterTransactions):
            "Later transactions changed the same properties as transaction \"\(transaction)\": "
                + "\(laterTransactions.joined(separator: Self.listSeparator)). Undo these transactions first, "
                + "or send \(MutationName.undoChange)(input: { txn: \"\(transaction)\", force: true }) to write the "
                + "inverse anyway."
        case .invalidFilter(let filter, let position, let detail, let example):
            "The filter \"\(filter)\" is not valid at \(position.lowerBound)..\(position.upperBound): \(detail). "
                + "Correct the filter, for example: \(example)"
        case .filterModelMissing(let filterError):
            "The engine has no filter model, so it cannot write a filter from English text. Send the text in the "
                + "filter language. \(filterError.message)"
        case .filterAgentFailed(let reason):
            "The filter agent stopped before it wrote a filter: \(reason) No attempt counts. Send the call again, or "
                + "send the text in the filter language."
        case .invalidTagName(let name):
            "The tag name \"\(name)\" gives an empty slug. \(Self.emptySlugCorrection)"
        case .reservedTagName:
            "\(Self.reservedSlugProblem(for: .tag)) \(Self.tagNameCorrection)"
        case .virtualTagName(let tag):
            "The slug \"\(tag.rawValue.lowercased())\" is the name of the virtual tag \(tag.rawValue), and the filter "
                + "\(FilterAtomKind.tag.sigil)\(tag.rawValue) matches only the virtual tag, so a tag cannot have it. "
                + Self.tagNameCorrection
        case .invalidSlug(let name):
            "The name \"\(name)\" gives an empty slug. \(Self.emptySlugCorrection)"
        case .reservedSlug(let type):
            "\(Self.reservedSlugProblem(for: type)) Use a name or an id that gives a different slug."
        case .invalidOrdinal(let ordinal):
            "The ordinal \"\(ordinal)\" is not a valid fractional index. Use before or after with a neighbor task, "
                + "or leave out the ordinal to put the task at the end of the column."
        case .conflictingPlacement(let fields):
            "The input gives more than one place field: \(fields.joined(separator: Self.listSeparator)). "
                + "Give only one of ordinal, before, and after, or give none of them to put the task at the end of "
                + "the column."
        case .staleWrite(let task, let givenVersion, let currentVersion):
            "The task \"\(task)\" changed after the version \"\(givenVersion)\": its current version is "
                + "\"\(currentVersion)\", so the call wrote nothing. Read the task again, and then send the call "
                + "again with ifVersion: \"\(currentVersion)\", or with no ifVersion to write over the change."
        case .emptyComment:
            "The comment is empty, so the call wrote nothing. Give a comment that tells why the task goes back, and "
                + "then send the call again."
        case .noPreviousColumn(let task, let column):
            "The task \"\(task)\" is in the first column \"\(column)\", so no column comes before it, and the call "
                + "wrote nothing. Give the column of the task, and then send the call again."
        case .boardBusy(let attempts):
            "The board changed during each of the \(attempts) commit attempts, so the call wrote nothing. "
                + "Send the call again."
        case .unreachableBoard(let reference):
            "This client reaches only the board of the folder of its session, so the call cannot name the board "
                + "\"\(reference)\". \(Self.ownBoardCorrection)"
        case .unreachableBoards(let field):
            "This client reaches only the board of the folder of its session, so the call cannot use \(field), "
                + "which reaches other boards. \(Self.ownBoardCorrection)"
        }
    }

    /// The correction for a call that reaches a board other than the board of the folder of its session.
    static let ownBoardCorrection = "Leave out the board ref, or name the board of that folder, and then send the "
        + "call again."

    /// Gives the noun of a node type in a message, for example `task`.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The name of the type, in lowercase.
    private static func noun(for type: PatchNodeType) -> String {
        type.rawValue.lowercased()
    }

    /// Gives the problem part of the message of a slug that the board URI reserves (plan.md §3.2).
    ///
    /// - Parameter type: The node type of the node that cannot have the slug.
    /// - Returns: The text, for example `The slug "board" is reserved for the board URI
    ///   kanban://<board-key>/board, so a column cannot have it.`
    private static func reservedSlugProblem(for type: PatchNodeType) -> String {
        let boardURI = "\(NodeURI.scheme)<board-key>\(LocalRef.separator)\(LocalRef.board)"
        return "The slug \"\(Slug.reservedForBoard)\" is reserved for the board URI \(boardURI), "
            + "so a \(noun(for: type)) cannot have it."
    }
}

// MARK: - Extension fields

extension KanbanError {
    /// The `extensions` key of the start of the span of a filter error.
    static let spanStartKey = "start"

    /// The `extensions` key of the end of the span of a filter error. The end is exclusive.
    static let spanEndKey = "end"

    /// The other keys of `extensions` for the error, beside `code`.
    ///
    /// `INVALID_FILTER` gives the span of its position in `start` and `end`. The span counts Swift `Character`s from
    /// the start of the filter, and `end` is exclusive, so the span is `start..<end`. These are the numbers of the
    /// message (`start..end`). `FILTER_MODEL_MISSING` gives the span of its filter error. Each other case gives no
    /// key.
    var extensionFields: [String: Map] {
        switch self {
        case .invalidFilter(_, let position, _, _):
            [
                Self.spanStartKey: .number(Number(position.lowerBound)),
                Self.spanEndKey: .number(Number(position.upperBound)),
            ]
        case .filterModelMissing(let filterError):
            filterError.extensionFields
        case .notFound, .nodesNotFound, .boardNotFound, .transactionBoardNotLoaded, .incompatibleBoard, .ambiguousID,
            .actorNotFound, .duplicateID, .columnNotEmpty, .dependencyCycle, .tagRenameCycle, .nothingToUndo,
            .undoConflict, .filterAgentFailed, .invalidTagName, .reservedTagName, .virtualTagName, .invalidSlug,
            .reservedSlug, .invalidOrdinal, .conflictingPlacement, .staleWrite, .emptyComment, .noPreviousColumn,
            .boardBusy, .unreachableBoard, .unreachableBoards:
            [:]
        }
    }
}

// MARK: - Call failure

extension KanbanError {
    /// Gives the ``KanbanError`` of an error that stops a call, when the caller can correct it: a ``KanbanError``
    /// itself, or the ``EventLogError/incompatibleBoard(directory:)`` of a `.kanban/` with Rust files
    /// (divergence.md Q6).
    ///
    /// - Parameter error: The error that stopped the call.
    /// - Returns: The error for the response, or `nil` for an I/O fault that the caller cannot correct.
    init?(callFailure error: any Error) {
        switch error {
        case let error as KanbanError:
            self = error
        case EventLogError.incompatibleBoard(let directory):
            self = .incompatibleBoard(directory: directory)
        default:
            return nil
        }
    }
}

// MARK: - Ambiguous reference

extension KanbanError {
    /// One node that an ambiguous ULID prefix matches, as the `AMBIGUOUS_ID` error lists it (divergence.md P5).
    struct AmbiguousMatch: Hashable, Sendable {
        /// The id that names this node alone, as the caller sends it: the short id with a leading ``ShortID/sigil``,
        /// for example `^ajv8v4t`, or the full ULID when a different node of the lookup has the same short id.
        let id: String

        /// The title of the task, or `nil` for a node with no title, for example a comment.
        let title: String?

        /// The match in a message: the id, then the title in quotes, for example `^ajv8v4t "Fix the build"`. A
        /// match with no title or with the empty title gives the id alone.
        var text: String {
            guard let title, !title.isEmpty else {
                return id
            }
            return "\(id) \"\(title)\""
        }
    }
}
