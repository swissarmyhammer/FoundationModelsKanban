import FoundationModelsExtras

/// The boards that one call of the `kanban` endpoint can read and change (EXTRAS-5; EXTRAS-9 rev 2, rule 4).
///
/// The ``GraphQLViewer`` of the call gives the reach. The agent of the session (no viewer) and a device of the user
/// reach each board. An `external` client reaches only the board of the folder of the call: the host checks that the
/// client owns the session of that folder, and the viewer names sessions, not folders, so no other board is safe to
/// give it.
enum BoardReach: Sendable {
    /// The call reads and changes each board: the board of its folder and each related board (plan.md §6.6).
    case allBoards

    /// The call reads and changes only the board of its folder. Each ref to a different board gives
    /// ``KanbanError/unreachableBoard(reference:)`` before the call looks for that board, so the response does not tell
    /// whether the board exists. The call loads no related board, so a cross-board dependency or assignee reads as a
    /// node that no loaded board has.
    case ownBoard

    /// The reach of the call of a viewer.
    ///
    /// - Parameter viewer: The client that makes the call, or `nil` for the agent of the session.
    init(viewer: GraphQLViewer?) {
        switch viewer?.trust {
        case nil, .userDevice?:
            self = .allBoards
        case .external?:
            self = .ownBoard
        }
    }

    /// `true` when the call can read the related boards.
    var readsRelatedBoards: Bool {
        switch self {
        case .allBoards: true
        case .ownBoard: false
        }
    }

    /// Checks that the call can use a field that reads or changes other boards, for example `boards`.
    ///
    /// - Parameter field: The name of the field or of the argument, for the error.
    /// - Throws: ``KanbanError/unreachableBoards(field:)`` when the call reaches only the board of its folder.
    func checkReachesOtherBoards(for field: String) throws(KanbanError) {
        guard readsRelatedBoards else {
            throw .unreachableBoards(field: field)
        }
    }
}
