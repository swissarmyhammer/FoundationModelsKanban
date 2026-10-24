import Foundation
import Graphiti

/// The arguments of the root query `cursor` (KANBAN-7).
struct CursorArguments: Codable, Sendable {
    /// The board whose cursor to give: a board key, a repo directory name, a path, or the URI of a board (plan.md
    /// §6.6). No value gives the cursor of the current board.
    let board: String?
}

extension BoardView {
    /// Gives the cursor of the change log of the board at the read of this view (KANBAN-7): `changes(after:)` with it
    /// gives each change of the board after the read.
    ///
    /// - Returns: The cursor.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` for the board when the read has no cursor: a board in memory
    ///   only, which has no change log.
    func changeCursor() throws(KanbanError) -> String {
        guard let cursor = source?.cursor else {
            throw .notFound(type: .board, reference: boardKey)
        }
        return cursor
    }
}

extension KanbanResolver {
    /// Resolves the root query `cursor`: the cursor of the current board, or of the board that `board` names, as the
    /// call reads it (KANBAN-7). The call reads the current board and its cursor inside the serial gate of the board.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The board, or no board for the current board.
    /// - Returns: The cursor.
    /// - Throws: An error of ``BoardStore/loadedView(ofBoard:)``, for example
    ///   ``KanbanError/unreachableBoard(reference:)`` when the call reaches only the board of its folder. An error of
    ///   ``BoardView/changeCursor()``.
    func cursor(context: KanbanContext, arguments: CursorArguments) async throws(KanbanError) -> String {
        try await context.store.loadedView(ofBoard: arguments.board).changeCursor()
    }
}

extension BoardObject {
    /// Resolves `Board.cursor`: the cursor of the change log of the board, as the call reads the board (KANBAN-7). The
    /// field reads no context and has no arguments.
    ///
    /// - Returns: The cursor.
    /// - Throws: An error of ``BoardView/changeCursor()``.
    func cursor(context _: KanbanContext, arguments _: NoArguments) throws(KanbanError) -> String {
        try view.changeCursor()
    }
}
