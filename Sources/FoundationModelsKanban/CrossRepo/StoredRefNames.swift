import Foundation

extension RelatedBoards {
    /// Gives the edge lists of a field with each ref to a node of a different board in its stored form (divergence.md
    /// M9): the URI with the current key of the loaded board that has the name of the URI. Thus a `dependsOn` URI with
    /// a board ID or an old name of a related board is stored with the git key of that board, and a URI with a name of
    /// the board of the field is stored as a local ref. A URI whose board the run did not load does not change.
    ///
    /// - Parameters:
    ///   - edges: The new list of each edge property of the field.
    ///   - key: The current key of the board of the field.
    /// - Returns: The edge lists in the stored form.
    func storedEdges(_ edges: [String: [StoredRef]], inBoard key: String) -> [String: [StoredRef]] {
        edges.mapValues { refs in refs.map { ref in storedRef(of: ref, inBoard: key) } }
    }

    /// Gives one ref in its stored form, with the rule of ``storedEdges(_:inBoard:)``.
    ///
    /// - Parameters:
    ///   - ref: The ref that the resolver gave.
    ///   - key: The current key of the board of the field.
    /// - Returns: The ref in the stored form.
    private func storedRef(of ref: StoredRef, inBoard key: String) -> StoredRef {
        guard case .remote(let uri) = ref, let board = board(forKey: uri.boardKey), board.key != uri.boardKey else {
            return ref
        }
        return StoredRef(uri: NodeURI(boardKey: board.key, ref: uri.ref), inBoard: key)
    }
}
