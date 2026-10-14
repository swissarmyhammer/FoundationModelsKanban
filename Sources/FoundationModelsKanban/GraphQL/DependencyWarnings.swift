import OrderedCollections

/// The warnings of the cross-board dependencies that a task field writes (divergence.md Q3 as P3 changed it, X3).
///
/// The write always stores a `dependsOn` URI or a body task URL to a different board, so the call does not fail. The
/// response tells the agent when the target cannot resolve: the board is found and has no task for the URI, or the
/// scan finds no board for the key of the URI. A target in the same board keeps its own rules.
enum DependencyWarnings {
    /// The code of the warning of a dependency on a task that a found board does not have.
    static let taskNotFoundCode = "DEPENDENCY_TASK_NOT_FOUND"

    /// The code of the warning of a dependency on a board that the scan cannot find.
    static let boardNotFoundCode = "DEPENDENCY_BOARD_NOT_FOUND"

    /// Gives the warnings of the cross-board targets that a task field writes.
    ///
    /// - Parameters:
    ///   - dependsOn: The new `dependsOn` list of the field, or `nil` when the field does not change the list.
    ///   - body: The new body of the field, or `nil` when the field does not change the body.
    ///   - key: The current key of the board of the task.
    ///   - related: The other boards as the graph rules of the field read them.
    /// - Returns: One warning for each target that cannot resolve, in the order of the list and then of the body. A
    ///   target is in the result one time.
    static func warnings(
        forDependsOn dependsOn: [StoredRef]?,
        body: String?,
        inBoard key: String,
        reading related: RelatedBoards
    ) -> [ResponseWarning] {
        let markers = DependencyMarkers.all(in: body ?? "").map { marker in StoredRef(uri: marker.uri, inBoard: key) }
        let targets = OrderedSet((dependsOn ?? []) + markers).compactMap { ref -> NodeURI? in
            guard case .remote(let uri) = ref else {
                return nil
            }
            return uri
        }
        return targets.compactMap { uri in warning(for: uri, in: related.state(ofDependencyOn: uri)) }
    }

    /// Gives the warning of one cross-board target.
    ///
    /// - Parameters:
    ///   - uri: The full URI of the target.
    ///   - state: What the run knows of the target.
    /// - Returns: The warning, or `nil` when the target resolves or the run cannot tell.
    private static func warning(for uri: NodeURI, in state: DependencyTargetState) -> ResponseWarning? {
        switch state {
        case .missingTask:
            ResponseWarning(
                message: "The dependency \(uri) names a task that the board \(uri.boardKey) does not have. The call "
                    + "stored the dependency: the task is blocked, and `unresolvedDependsOn` lists the URI until the "
                    + "board has this task. Correct the URI, or remove the dependency.",
                code: taskNotFoundCode
            )
        case .boardNotFound:
            ResponseWarning(
                message: "The dependency \(uri) names the board \(uri.boardKey), and the scan finds no board with "
                    + "this key. The call stored the dependency, because the repo can be absent on this machine: the "
                    + "task is blocked, and `unresolvedDependsOn` lists the URI. Correct the key when it is wrong.",
                code: boardNotFoundCode
            )
        case .found, .unknown:
            nil
        }
    }
}
