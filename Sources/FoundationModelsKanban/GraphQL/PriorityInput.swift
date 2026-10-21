import FoundationModelsExtras
import Graphiti
import GraphQL

/// The value of a `priority` field in a task input, as the GraphQL `Priority` scalar (divergence.md P2 and K15).
///
/// A task has no priority field: the place of the task in its column is its priority. The agent can still send
/// `priority`, `prio`, or `urgent` on `addTask` and `updateTask`. The value can be a string, an unquoted word, a
/// Boolean, or a number, so the scalar keeps the text of each value: `"high"` and `high` give `high`, `true` gives
/// `true`, and `5` gives `5`. Graphiti decodes each input through `MapDecoder`, and the text form keeps a number from
/// becoming a Boolean on that path. The Codable form is the text, the same as ``NodeID``.
struct PriorityValue: Codable, Sendable, Hashable {
    /// The GraphQL name of the scalar.
    static let name = "Priority"

    /// The text of the value as the agent wrote it, without the quotes of a string.
    let text: String
}

extension PriorityValue {
    /// Decodes the value from its text.
    ///
    /// - Parameter decoder: The decoder that holds the text.
    /// - Throws: A `DecodingError` when the value is not text.
    init(from decoder: any Decoder) throws {
        try self.init(text: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the value as its text.
    ///
    /// - Parameter encoder: The encoder that gets the text.
    /// - Throws: An error from the encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    /// Gives a value from the variables as its text.
    ///
    /// - Parameters:
    ///   - map: The value from the variables, for example `.bool(true)` or `.number(1)`.
    ///   - coders: The coders of the schema. The scalar does not use them.
    /// - Returns: The text of the value, as a string.
    @Sendable
    static func parseValue(_ map: Map, coders _: Coders) -> Map {
        .string(map.plainText)
    }

    /// Gives a literal value of the document as its text.
    ///
    /// - Parameters:
    ///   - literal: The literal value in the document, for example `"high"`, `high`, `true`, or `5`.
    ///   - coders: The coders of the schema. The scalar does not use them.
    /// - Returns: The text of the value, as a string. A list, an object, or `null` gives the compact JSON form of its
    ///   value, for example `["high"]`.
    /// - Throws: A `GraphQLError` when a number in a list or an object literal is not a valid number.
    @Sendable
    static func parseLiteral(_ literal: GraphQL.Value, coders _: Coders) throws -> Map {
        let text = switch literal {
        case let value as StringValue: value.value
        case let value as EnumValue: value.value
        case let value as IntValue: value.value
        case let value as FloatValue: value.value
        case let value as BooleanValue: String(value.value)
        default: try valueFromASTUntyped(valueAST: literal).plainText
        }
        return .string(text)
    }

    /// The move in its column that the value gives the task, by the fixed table.
    var move: PriorityMove {
        PriorityMove(of: self)
    }

    /// Gives the warnings of the priority value of an input.
    ///
    /// A value that moves the task wins over an explicit ordinal of the same input: the move gives the place of the
    /// task, and a second warning tells that the call ignored the ordinal.
    ///
    /// - Parameters:
    ///   - value: The priority value of the input, or `nil` when the input has none.
    ///   - ordinal: The explicit ordinal of the input, or `nil` when the input has none.
    /// - Returns: One warning that tells the move of the value, then a warning for an ordinal that the move overrode,
    ///   or no warning when the input has no priority value.
    static func warnings(of value: PriorityValue?, overriding ordinal: String? = nil) -> [ResponseWarning] {
        guard let value else {
            return []
        }
        let move = value.move
        guard move != .stay, let ordinal else {
            return [move.warning(for: value)]
        }
        return [move.warning(for: value), move.ordinalWarning(ignoring: ordinal, for: value)]
    }
}

extension Map {
    /// The text of the value: the text of a string, a Boolean, or a number, or the JSON form of any other value. The
    /// priority scalar reads a value from the variables with it, and `collectBoards` shows a field value with it.
    var plainText: String {
        switch self {
        case .string(let text): text
        case .bool(let flag): String(flag)
        case .number(let number): number.stringValue
        case .undefined, .null, .array, .dictionary: description
        }
    }
}

/// The move in its column that a priority value gives a task (divergence.md K15).
enum PriorityMove: Sendable {
    /// The task goes before the first task of its column.
    case toTop

    /// The task goes after the last task of its column.
    case toEnd

    /// The task keeps its place.
    case stay

    /// The code of the warning of a priority value, in `extensions.warnings`.
    static let warningCode = "PRIORITY_IS_POSITION"

    /// The code of the warning of an explicit ordinal that a priority move overrode, in `extensions.warnings`.
    static let ordinalIgnoredCode = "ORDINAL_IGNORED"

    /// The fixed table of the values, in lowercase. A value that is not in the table, for example a bare number,
    /// makes no move.
    private static let movesByValue: [String: PriorityMove] = [
        "urgent": .toTop, "critical": .toTop, "high": .toTop, "p0": .toTop, "p1": .toTop, "true": .toTop,
        "low": .toEnd, "p3": .toEnd, "p4": .toEnd,
        "medium": .stay, "normal": .stay, "p2": .stay,
    ]

    /// The end of each warning: why the move happens, and what the agent can do in its place.
    private static let warningAdvice = "A task has no priority field: the place in the column is the priority. "
        + "Use moveTask with before or after to change the place, or filter with #HIGH, #MEDIUM, or #LOW."

    /// The end of the warning of an ordinal that a priority move overrode: what the agent can do in its place.
    private static let ordinalIgnoredAdvice = "Give a priority value or an ordinal, not both."

    /// Gives the move of a priority value by the fixed table. The case of the value does not matter.
    ///
    /// - Parameter value: The priority value of the input.
    init(of value: PriorityValue) {
        self = Self.movesByValue[value.text.lowercased()] ?? .stay
    }

    /// The part of the warning sentence that tells what the move did.
    private var effect: String {
        switch self {
        case .toTop: "moved the task to the top of its column."
        case .toEnd: "moved the task to the end of its column."
        case .stay: "made no move."
        }
    }

    /// Gives the warning of the move for the response.
    ///
    /// - Parameter value: The priority value of the input. The warning quotes its text.
    /// - Returns: The warning, for example "The priority value `high` moved the task to the top of its column. …".
    func warning(for value: PriorityValue) -> ResponseWarning {
        warning(opening: "The", for: value, advice: Self.warningAdvice, code: Self.warningCode)
    }

    /// Gives the warning of an explicit ordinal that the move overrode.
    ///
    /// - Parameters:
    ///   - ordinal: The explicit ordinal of the input. The warning quotes it.
    ///   - value: The priority value of the input. The warning quotes its text.
    /// - Returns: The warning, for example "The ordinal `8180` was ignored: the priority value `high` moved the task to
    ///   the top of its column. …".
    func ordinalWarning(ignoring ordinal: String, for value: PriorityValue) -> ResponseWarning {
        warning(
            opening: "The ordinal `\(ordinal)` was ignored: the",
            for: value,
            advice: Self.ordinalIgnoredAdvice,
            code: Self.ordinalIgnoredCode
        )
    }

    /// Builds a warning of the move. Each warning has the one sentence shape
    /// "<opening> priority value `<text>` <effect> <advice>".
    ///
    /// - Parameters:
    ///   - opening: The words before "priority value", for example "The".
    ///   - value: The priority value of the input. The warning quotes its text.
    ///   - advice: The end of the message, after the effect of the move.
    ///   - code: The code of the warning in `extensions.warnings`.
    /// - Returns: The warning.
    private func warning(
        opening: String,
        for value: PriorityValue,
        advice: String,
        code: String
    ) -> ResponseWarning {
        ResponseWarning(message: "\(opening) priority value `\(value.text)` \(effect) \(advice)", code: code)
    }
}

extension Graph {
    /// Gives the ordinal of a task that a priority move puts in a column.
    ///
    /// - Parameters:
    ///   - move: The move.
    ///   - column: The local ref of the column.
    ///   - task: The local ref of the moved task, or `nil` for a new task. The column order does not count this task.
    /// - Returns: An ordinal before the first task of the column for ``PriorityMove/toTop``, after the last task for
    ///   ``PriorityMove/toEnd``, or `nil` for ``PriorityMove/stay``.
    func ordinal(for move: PriorityMove, inColumn column: LocalRef, excluding task: LocalRef?) -> Ordinal? {
        switch move {
        case .toTop:
            tasks(inColumn: column, excluding: task).first.map { first in Ordinal(before: first.ordinal) } ?? .first
        case .toEnd:
            nextOrdinal(inColumn: column, excluding: task)
        case .stay:
            nil
        }
    }

    /// Gives the column where a task shows: its column when the column is live, else the first column.
    ///
    /// - Parameter task: The task.
    /// - Returns: The local ref of the column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the board has no live column.
    func displayColumn(of task: TaskNode) throws(KanbanError) -> LocalRef {
        try columnRef(atSlot: ColumnOrder(of: self).displaySlot(of: task.column))
    }
}
