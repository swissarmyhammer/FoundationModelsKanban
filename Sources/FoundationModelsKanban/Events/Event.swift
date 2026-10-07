import Foundation
import ULID

/// One line of a node log: one property patch on one node, plus the envelope (plan.md §5.1, §12 item 28).
///
/// The line is a complete GraphQL request to the internal `patch` mutation: `query` is the mutation, and
/// `variables` holds the ``PatchInput``. The envelope tells when, by whom, and in which transaction the patch was
/// made. Each ref is in the stored form, so a line never holds the key of its own board.
struct Event: Codable, Hashable, Sendable {
    /// The GraphQL request of each line: the internal `patch` mutation with the patch in the variable `p`.
    static let patchQuery = "mutation($p: PatchInput!) { patch(input: $p) }"

    /// The `variables` of the GraphQL request of a line.
    struct Variables: Codable, Hashable, Sendable {
        /// The keys of the variables. The patch is the variable `p` of ``Event/patchQuery``.
        private enum CodingKeys: String, CodingKey {
            case patch = "p"
        }

        /// The patch.
        let patch: PatchInput
    }

    /// The event ULID. The replay order is the sort order of this value.
    let id: ULID

    /// The transaction ULID. All patches of one tool call have the same value (plan.md §6.5).
    let txn: ULID

    /// The names of the public mutations of the tool call, for example `moveTask`. Only `history` reads them.
    let ops: [String]

    /// The time of the event. It is the only time value in the event.
    let at: DateTime

    /// The local ref of the actor that made the change, in the board of this log.
    let actor: LocalRef

    /// The keys of the other boards that the transaction changes, or `nil` when it changes only this board. The key
    /// of this board is never in the list.
    let boards: [String]?

    /// The transaction that this transaction reverses, only on the patches of `undo` and `redo`.
    let undoes: ULID?

    /// The GraphQL document of the request.
    let query: String

    /// The variables of the request, which hold the patch.
    let variables: Variables

    /// The patch of the event.
    var patch: PatchInput {
        variables.patch
    }

    /// Makes an event with a request to the internal `patch` mutation.
    ///
    /// - Parameters:
    ///   - id: The event ULID.
    ///   - txn: The transaction ULID.
    ///   - ops: The names of the public mutations of the tool call.
    ///   - at: The time of the event.
    ///   - actor: The local ref of the actor.
    ///   - boards: The keys of the other boards that the transaction changes, or `nil` for this board only.
    ///   - undoes: The transaction that this transaction reverses, or `nil`.
    ///   - patch: The patch.
    init(
        id: ULID,
        txn: ULID,
        ops: [String],
        at: DateTime,
        actor: LocalRef,
        boards: [String]? = nil,
        undoes: ULID? = nil,
        patch: PatchInput
    ) {
        self.id = id
        self.txn = txn
        self.ops = ops
        self.at = at
        self.actor = actor
        self.boards = boards
        self.undoes = undoes
        query = Self.patchQuery
        variables = Variables(patch: patch)
    }
}

// MARK: - Line

extension Event {
    /// The encoder of a line: sorted keys, and slashes that are not escaped, so that each ref stays readable and
    /// each line has one canonical form.
    private static let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Reads an event from one line of a log.
    ///
    /// - Parameter line: The text of the line, with no line break.
    /// - Throws: ``EventError/invalidRef(_:)`` when a ref is not valid. ``EventError/malformed(detail:)`` when the
    ///   line is not JSON or a field is missing or has the wrong shape. Another ``EventError`` when the patch breaks
    ///   a rule of ``PatchInput``.
    init(parsing line: String) throws(EventError) {
        do {
            self = try JSONDecoder().decode(Self.self, from: Data(line.utf8))
        } catch let error as EventError {
            throw error
        } catch let error as NodeRefError {
            throw .invalidRef(error)
        } catch {
            throw .malformed(detail: String(describing: error))
        }
    }

    /// Writes the event as one log line: JSON with sorted keys and no line break.
    ///
    /// - Returns: The text of the line.
    /// - Throws: ``EventError/unencodable(detail:)`` when a value cannot be JSON, for example a number that is not
    ///   finite.
    func encodedLine() throws(EventError) -> String {
        do {
            return String(decoding: try Self.lineEncoder.encode(self), as: UTF8.self)
        } catch {
            throw .unencodable(detail: String(describing: error))
        }
    }
}

// MARK: - Errors

/// An error from the read or the write of a log line, or from a patch that breaks a rule of the log.
///
/// The loader skips a line that does not decode (plan.md §5.3). The ``KanbanError`` catalog has no code for a bad
/// line, because the caller of the tool does not write lines.
enum EventError: Error, Hashable, Sendable {
    /// The line is not JSON, or a field is missing or has the wrong shape. The detail is the decoder error.
    case malformed(detail: String)

    /// A ref in the line is not a valid local ref or URI.
    case invalidRef(NodeRefError)

    /// The `type` of the patch is not the type of its `node`.
    case typeMismatch(node: LocalRef, type: PatchNodeType)

    /// The patch sets a time value. Replay derives each time value from the envelope `at` (plan.md §5.3).
    case timeProperty(name: String)

    /// A ref property has a value that is not a ref, or a plain property has a ref.
    case refMismatch(property: String)

    /// The event cannot be written as JSON. The detail is the encoder error.
    case unencodable(detail: String)
}
