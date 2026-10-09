import Foundation

/// An error that the tool returns to the caller in the `errors` list of a GraphQL response (plan.md §4.4).
///
/// Each case has one fixed ``code`` and a ``message`` that tells the caller how to correct the call. Each case
/// holds the data that its message needs, for example the matching short ids of an ambiguous reference.
///
/// The type does not use the GraphQL engine. ``responseError(at:)`` makes the GraphQL error JSON with `Codable`.
enum KanbanError: Error, Hashable, Sendable {
    /// `INVALID_VARIABLES`: the `variables` of the call are not a JSON object. The value tells what the call sent,
    /// for example `a number`.
    case invalidVariables(received: String)

    /// `NOT_FOUND`: no node of the type has the reference.
    case notFound(type: PatchNodeType, reference: String)

    /// `NOT_FOUND`: the scan finds no board for the board ref (plan.md §6.6). The search roots are the places that
    /// the scan looked in, in scan order.
    case boardNotFound(reference: String, searchRoots: [String])

    /// `AMBIGUOUS_ID`: the reference is a prefix of more than one id. The matches are the short ids of these ids.
    case ambiguousID(reference: String, matches: [ShortID])

    /// `AMBIGUOUS_ID`: the reference matches more than one id, and two or more of these ids have the same short id
    /// (a merge can make such ids). A short id cannot name one of them, so the ids are the full ULIDs of the matches.
    case sharedShortID(reference: String, ids: [String])

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
    /// failed, the detail tells the problem, and the example is one correct filter.
    case invalidFilter(filter: String, position: Range<Int>, detail: String, example: String)

    /// `INVALID_TAG_NAME`: the tag name gives an empty slug.
    case invalidTagName(name: String)

    /// `INVALID_SLUG`: the name of a column or an actor gives an empty slug.
    case invalidSlug(name: String)

    /// `INVALID_ORDINAL`: the ordinal is not a valid fractional index.
    case invalidOrdinal(ordinal: String)

    /// `CONFLICTING_PLACEMENT`: the input of a move gives more than one place field. The fields are the names of
    /// these place fields, in the order of the input type.
    case conflictingPlacement(fields: [String])

    /// `BOARD_BUSY`: the log of the board changed during each commit attempt (plan.md §5.4).
    case boardBusy(attempts: Int)

    /// `SUBSCRIPTION_NOT_IN_TOOL`: the call sent a `subscription` through the tool.
    case subscriptionNotInTool

    /// `GRAPHQL_PARSE_FAILED`: the document has a syntax error. The detail is the message of the GraphQL parser.
    case graphQLParseFailed(detail: String)

    /// `GRAPHQL_VALIDATION_FAILED`: the document is not valid for the schema, for example it has an unknown field
    /// or an argument of the wrong type. The detail is the message of the GraphQL engine, with its "did you mean"
    /// suggestion.
    case graphQLValidationFailed(detail: String)

    /// `AMBIGUOUS_NAME`: the name rewrite matches a name of the document to more than one name of the schema
    /// (plan.md §4.5). The matches are these names.
    case ambiguousName(name: String, matches: [String])

    /// `INTERNAL`: a fault that is not a ``KanbanError``, for example an ``EventError`` of a resolver. The detail is
    /// the message of the GraphQL engine.
    case internalFailure(detail: String)
}

// MARK: - Code and message

extension KanbanError {
    /// The text between two items of a list in a message.
    static let listSeparator = ", "

    /// The text between two steps of a cycle path in a message.
    static let pathSeparator = " -> "

    /// The correction for a name that gives an empty slug.
    static let emptySlugCorrection = "Use a name that has one or more letters or digits."

    /// The code of the error, as `extensions.code` gives it, for example `NOT_FOUND`.
    var code: String {
        switch self {
        case .invalidVariables: "INVALID_VARIABLES"
        case .notFound, .boardNotFound: "NOT_FOUND"
        case .ambiguousID, .sharedShortID: "AMBIGUOUS_ID"
        case .actorNotFound: "ACTOR_NOT_FOUND"
        case .duplicateID: "DUPLICATE_ID"
        case .columnNotEmpty: "COLUMN_NOT_EMPTY"
        case .dependencyCycle: "DEPENDENCY_CYCLE"
        case .tagRenameCycle: "TAG_RENAME_CYCLE"
        case .nothingToUndo: "NOTHING_TO_UNDO"
        case .undoConflict: "UNDO_CONFLICT"
        case .invalidFilter: "INVALID_FILTER"
        case .invalidTagName: "INVALID_TAG_NAME"
        case .invalidSlug: "INVALID_SLUG"
        case .invalidOrdinal: "INVALID_ORDINAL"
        case .conflictingPlacement: "CONFLICTING_PLACEMENT"
        case .boardBusy: "BOARD_BUSY"
        case .subscriptionNotInTool: "SUBSCRIPTION_NOT_IN_TOOL"
        case .graphQLParseFailed: "GRAPHQL_PARSE_FAILED"
        case .graphQLValidationFailed: "GRAPHQL_VALIDATION_FAILED"
        case .ambiguousName: "AMBIGUOUS_NAME"
        case .internalFailure: "INTERNAL"
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .invalidVariables(let received):
            "The variables are not a JSON object. The call sent \(received). Send the variables as a JSON object, "
                + "or as a string that holds a JSON object, for example {\"id\": \"^ajv8v4t\"}."
        case .notFound(let type, let reference):
            "No \(Self.noun(for: type)) has the reference \"\(reference)\". Query the board to get the correct ids, "
                + "and then send the call again."
        case .boardNotFound(let reference, let searchRoots):
            "No board has the reference \"\(reference)\". The scan looked for git repos in: "
                + "\(searchRoots.joined(separator: Self.listSeparator)). Use a board key, a repo directory name, "
                + "or a repo path from these places, and then send the call again."
        case .ambiguousID(let reference, let matches):
            "The reference \"\(reference)\" matches more than one id: \(Self.sigilList(of: matches)). "
                + "Send one of these short ids."
        case .sharedShortID(let reference, let ids):
            "The reference \"\(reference)\" matches more than one id: \(ids.joined(separator: Self.listSeparator)). "
                + "These ids have the same short id, so send one of these full ids."
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
                + "and then send undo(txn: <id>)."
        case .undoConflict(let transaction, let laterTransactions):
            "Later transactions changed the same properties as transaction \"\(transaction)\": "
                + "\(laterTransactions.joined(separator: Self.listSeparator)). Undo these transactions first, "
                + "or send undo(txn: \"\(transaction)\", force: true) to write the inverse anyway."
        case .invalidFilter(let filter, let position, let detail, let example):
            "The filter \"\(filter)\" is not valid at \(position.lowerBound)..\(position.upperBound): \(detail). "
                + "Correct the filter, for example: \(example)"
        case .invalidTagName(let name):
            "The tag name \"\(name)\" gives an empty slug. \(Self.emptySlugCorrection)"
        case .invalidSlug(let name):
            "The name \"\(name)\" gives an empty slug. \(Self.emptySlugCorrection)"
        case .invalidOrdinal(let ordinal):
            "The ordinal \"\(ordinal)\" is not a valid fractional index. Use before or after with a neighbor task, "
                + "or leave out the ordinal to put the task at the end of the column."
        case .conflictingPlacement(let fields):
            "The input gives more than one place field: \(fields.joined(separator: Self.listSeparator)). "
                + "Give only one of ordinal, before, and after, or give none of them to put the task at the end of "
                + "the column."
        case .boardBusy(let attempts):
            "The board changed during each of the \(attempts) commit attempts, so the call wrote nothing. "
                + "Send the call again."
        case .subscriptionNotInTool:
            "The tool does not run a subscription. Use board { history(since: <txn>) } "
                + "to get the changes after a known transaction."
        case .graphQLParseFailed(let detail), .graphQLValidationFailed(let detail), .internalFailure(let detail):
            detail
        case .ambiguousName(let name, let matches):
            "The name \"\(name)\" matches more than one name: \(matches.joined(separator: Self.listSeparator)). "
                + "Use one of these names."
        }
    }

    /// Gives the noun of a node type in a message, for example `task`.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The name of the type, in lowercase.
    private static func noun(for type: PatchNodeType) -> String {
        type.rawValue.lowercased()
    }

    /// Gives a list of short ids in a message, each with a leading ``ShortID/sigil``, for example
    /// `^ajv8v4t, ^rc9rb4g`.
    ///
    /// - Parameter shortIDs: The short ids, in the order to show.
    /// - Returns: The list text.
    private static func sigilList(of shortIDs: [ShortID]) -> String {
        shortIDs.map { "\(ShortID.sigil)\($0.value)" }.joined(separator: listSeparator)
    }
}

// MARK: - Ambiguous reference

extension KanbanError {
    /// Makes the `AMBIGUOUS_ID` error of a reference that matches more than one id.
    ///
    /// The error gives the form of the ids that names one id: the short ids when they are unique
    /// (``ambiguousID(reference:matches:)``), else the full ids (``sharedShortID(reference:ids:)``).
    ///
    /// - Parameters:
    ///   - reference: The reference as the caller wrote it.
    ///   - ulids: The text of each ULID that the reference matches, in the order to show.
    /// - Returns: The error.
    static func ambiguity(of reference: String, among ulids: [String]) -> KanbanError {
        let shortIDs = ulids.map(ShortID.init(ofULIDString:))
        guard Set(shortIDs).count == shortIDs.count else {
            return .sharedShortID(reference: reference, ids: ulids)
        }
        return .ambiguousID(reference: reference, matches: shortIDs)
    }
}

// MARK: - GraphQL error JSON

extension KanbanError {
    /// One step of the `path` of a GraphQL error: the response key of a field, or the index of a list item.
    ///
    /// The JSON form is a string for a key and a number for an index, as the GraphQL specification tells.
    enum PathComponent: Codable, Hashable, Sendable {
        /// The response key of a field, for example `addTask`.
        case key(String)

        /// The index of an item in a list.
        case index(Int)

        /// Reads a path step from a JSON number or a JSON string.
        ///
        /// - Parameter decoder: The decoder that holds one value.
        /// - Throws: A `DecodingError` when the value is not a number or a string.
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let position = try? container.decode(Int.self) {
                self = .index(position)
            } else {
                self = .key(try container.decode(String.self))
            }
        }

        /// Writes the path step as a JSON string for a key, or a JSON number for an index.
        ///
        /// - Parameter encoder: The encoder that gets one value.
        /// - Throws: An error from the encoder.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .key(let name):
                try container.encode(name)
            case .index(let position):
                try container.encode(position)
            }
        }
    }

    /// The GraphQL error JSON of a ``KanbanError``: `{ message, path, extensions: { code } }`.
    struct ResponseError: Codable, Hashable, Sendable {
        /// The `extensions` object of a GraphQL error.
        struct Extensions: Codable, Hashable, Sendable {
            /// The keys of the `extensions` object.
            enum CodingKeys: String, CodingKey {
                /// The key of the code.
                case code
            }

            /// The code of the error, for example `NOT_FOUND`.
            let code: String
        }

        /// The message of the error.
        let message: String

        /// The path to the response field of the error. The path is empty when no field caused the error.
        // The synthesized `Encodable` and `Hashable` conformances read this property; periphery sees no reader.
        // periphery:ignore
        let path: [PathComponent]

        /// The `extensions` object, which holds the code.
        let extensions: Extensions
    }

    /// Makes the GraphQL error JSON of the error.
    ///
    /// - Parameter path: The path to the response field of the error. Leave it empty when no field caused the
    ///   error, for example for `INVALID_VARIABLES`.
    /// - Returns: The error with its ``message``, the path, and its ``code`` in `extensions`.
    func responseError(at path: [PathComponent] = []) -> ResponseError {
        ResponseError(message: message, path: path, extensions: ResponseError.Extensions(code: code))
    }

    /// The JSON of a response that holds only errors, and no `data`.
    private struct ErrorResponse: Encodable {
        /// The errors of the response.
        // The synthesized `Encodable` conformance reads this property; periphery sees no reader.
        // periphery:ignore
        let errors: [ResponseError]
    }

    /// Makes the GraphQL response of a call that fails as a whole with this error, for example `BOARD_BUSY` (plan.md
    /// §5.4 step 5.2): `{"errors": [...]}`, with no `data`. The keys are in sorted order, and a `/` is not escaped,
    /// the same as each other response of the tool.
    ///
    /// - Returns: The response as JSON text.
    /// - Throws: An error from the JSON encoder.
    func responseJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(ErrorResponse(errors: [responseError()])), as: UTF8.self)
    }
}
