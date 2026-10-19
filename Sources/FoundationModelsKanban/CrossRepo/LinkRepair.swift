import Foundation

/// One link that `Mutation.repairLinks` reports (divergence.md M9): the GraphQL `LinkRepair` type. A link with an old
/// board name gets the current name of its board. A dangling link is in the list with no new target, and the call
/// does not change it.
struct LinkRepair: Sendable {
    /// The link as the board stores it before the rewrite.
    let link: StoredLink

    /// The checked link before the rewrite: the board that holds it, and its class.
    let check: LinkCheck

    /// The URI that the rewrite writes in place of the target, or `nil` when the call does not change the link.
    let newURI: NodeURI?

    /// The text of the URI that the rewrite writes, or `nil` when the call does not change the link.
    var newTarget: String? {
        newURI?.description
    }

    /// Makes the repair of one checked link.
    ///
    /// - Parameters:
    ///   - link: The link as the board stores it.
    ///   - check: The check of the link.
    /// - Returns: The repair: an `OLD_NAME` link gets the URI with the current name of its board, and a `DANGLING`
    ///   link gets no new URI. `nil` for an `OK` link and a `MISSING_NODE` link, which the call does not report.
    init?(of link: StoredLink, checked check: LinkCheck) {
        switch check.status {
        case .oldName:
            newURI = check.currentName.map { name in NodeURI(boardKey: name, ref: link.target.ref) }
        case .dangling:
            newURI = nil
        case .ok, .missingNode:
            return nil
        }
        self.link = link
        self.check = check
    }
}

extension LinkField {
    /// The set-valued property of a task that holds a link of this field, or `nil` for a link in the body.
    var edgeProperty: String? {
        switch self {
        case .dependsOn: PropertyName.dependsOn
        case .assignee: PropertyName.assignees
        case .body, .tombstone: nil
        }
    }

    /// Rewrites each link of this field to one URI in a body to a different URI. A field whose links are edges does
    /// not change the body.
    ///
    /// - Parameters:
    ///   - body: The Markdown body of the task that holds the link.
    ///   - old: The URI that the link holds now.
    ///   - new: The URI that the link gets.
    /// - Returns: The body after the rewrite.
    func rewriting(_ body: String, from old: NodeURI, to new: NodeURI) -> String {
        switch self {
        case .body: DependencyMarkers.replacing(markersOf: old, with: new, in: body)
        case .tombstone: MovedTaskLine.replacing(old, with: new, in: body)
        case .dependsOn, .assignee: body
        }
    }
}
