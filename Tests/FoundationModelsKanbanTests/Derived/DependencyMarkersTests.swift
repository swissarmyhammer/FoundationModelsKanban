import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the dependency markers: the full `kanban://` task URLs in a task body, their resolve at read time, and the
/// remove of a URL from a body (plan.md §6.1).
@Suite("Dependency markers")
struct DependencyMarkersTests {
    /// The time of each test node.
    static let time = DateTime(Date(timeIntervalSince1970: .zero))

    /// The key of the current board.
    static let boardKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The key of a different board.
    static let otherBoardKey = "github.com/swissarmyhammer/swissarmyhammer"

    /// The ULID text of the task that has the body.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of a task that the first task depends on.
    static let targetULID = "01KT6R7Q0ZB4X1N9C2D3E4F5G6"

    /// The ULID text of a task that the graph does not have, or that is in a different board.
    static let missingULID = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The short id of the target task: the last seven characters of its ULID, in lowercase.
    static let targetShortID = "^3e4f5g6"

    /// Gives the ULID of a ULID text.
    ///
    /// - Parameter text: The ULID text.
    /// - Returns: The ULID.
    /// - Throws: An error when the text is not a ULID.
    static func ulid(of text: String) throws -> ULID {
        try #require(ULID(ulidString: text))
    }

    /// Gives the URL text of a task.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - key: The key of the board of the task.
    /// - Returns: The URL, for example `kanban://local/repo/task/01K…`.
    static func url(ofTask text: String, inBoard key: String = boardKey) -> String {
        "\(NodeURI.scheme)\(key)/task/\(text)"
    }

    /// Gives the URI of a task.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - key: The key of the board of the task.
    /// - Returns: The URI.
    /// - Throws: An error when the text is not a ULID.
    static func uri(ofTask text: String, inBoard key: String = boardKey) throws -> NodeURI {
        NodeURI(boardKey: key, ref: .task(try ulid(of: text)))
    }

    /// Gives a test task.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - body: The body of the task.
    ///   - dependsOn: The `dependsOn` edges of the task.
    /// - Returns: The task.
    /// - Throws: An error when the text is not a ULID.
    static func task(
        withULID text: String = taskULID,
        body: String = "",
        dependsOn: [EdgeTarget] = []
    ) throws -> TaskNode {
        let fields = NodeFields(body: body, created: time, updated: time)
        return TaskNode(id: try ulid(of: text), fields: fields, dependsOn: dependsOn)
    }

    /// Puts the target task and a task with a body into a graph, and gives the dependencies of the task with the
    /// body.
    ///
    /// - Parameters:
    ///   - body: The body of the task.
    ///   - dependsOn: The `dependsOn` edges of the task.
    /// - Returns: The dependencies of the task, and the slot of the target task.
    /// - Throws: An error when a test ULID is not valid.
    static func dependencies(
        ofBody body: String,
        dependsOn: [EdgeTarget] = []
    ) throws -> (dependencies: [EdgeTarget], targetSlot: Int) {
        var graph = Graph()
        let targetSlot = graph.update(with: .task(try task(withULID: targetULID)))
        let slot = graph.update(with: .task(try task(body: body, dependsOn: dependsOn)))
        let stored = try #require(graph.node(at: slot)?.state as? TaskNode)
        return (graph.dependencies(of: stored, inBoard: boardKey), targetSlot)
    }

    // MARK: - Resolve

    @Test("A task URL of this board in the body gives a same-board dependency")
    func sameBoardURLGivesSlot() throws {
        let result = try Self.dependencies(ofBody: "Wait for \(Self.url(ofTask: Self.targetULID)) first.")
        #expect(result.dependencies == [.slot(result.targetSlot)])
    }

    @Test("A task URL of this board to a task that the graph does not have stays an unresolved local ref")
    func sameBoardURLToMissingTaskStaysLocal() throws {
        let result = try Self.dependencies(ofBody: Self.url(ofTask: Self.missingULID))
        let missing = LocalRef.task(try Self.ulid(of: Self.missingULID))
        #expect(result.dependencies == [.unresolved(.local(missing))])
    }

    @Test("A task URL of a different board gives a cross-board dependency")
    func otherBoardURLGivesRemoteRef() throws {
        let body = "Blocked by \(Self.url(ofTask: Self.targetULID, inBoard: Self.otherBoardKey))"
        let result = try Self.dependencies(ofBody: body)
        let remote = try Self.uri(ofTask: Self.targetULID, inBoard: Self.otherBoardKey)
        #expect(result.dependencies == [.unresolved(.remote(remote))])
    }

    @Test("A short id, a bare ULID, a tag URL, a column URL, or a board URL in the body gives no dependency")
    func otherTextGivesNoDependency() throws {
        let scheme = NodeURI.scheme
        let body = """
            \(Self.targetShortID) and \(Self.targetULID)
            \(scheme)\(Self.boardKey)/tag/bug
            \(scheme)\(Self.boardKey)/column/doing
            \(scheme)\(Self.boardKey)/board
            """
        let result = try Self.dependencies(ofBody: body)
        #expect(result.dependencies.isEmpty)
    }

    @Test("The dependencies are the edges and the markers together, with no duplicates")
    func edgesAndMarkersJoinWithNoDuplicates() throws {
        let remoteURL = Self.url(ofTask: Self.missingULID, inBoard: Self.otherBoardKey)
        let targetURL = Self.url(ofTask: Self.targetULID)
        let body = "\(targetURL)\n\(remoteURL)\n\(targetURL)"
        let edge = EdgeTarget.unresolved(.local(.task(try Self.ulid(of: Self.targetULID))))
        let result = try Self.dependencies(ofBody: body, dependsOn: [edge])
        let remote = try Self.uri(ofTask: Self.missingULID, inBoard: Self.otherBoardKey)
        #expect(result.dependencies == [.slot(result.targetSlot), .unresolved(.remote(remote))])
    }

    // MARK: - Find

    @Test("A marker ends before Markdown punctuation and before the end of a sentence")
    func markerEndsBeforePunctuation() throws {
        let url = Self.url(ofTask: Self.targetULID)
        let mentions = ["(\(url)),", "<\(url)>,", "[link](\(url)).", "See \(url).", "\"\(url)\";", "`\(url)`!"]
        let body = mentions.joined(separator: " ")
        let markers = DependencyMarkers.all(in: body)
        let target = try Self.uri(ofTask: Self.targetULID)
        #expect(markers.map(\.uri) == Array(repeating: target, count: mentions.count))
        #expect(markers.map { marker in String(body[marker.range]) } == Array(repeating: url, count: mentions.count))
    }

    @Test("The scheme and the ULID of a marker ignore case")
    func markerIgnoresCase() throws {
        let body = "KANBAN://\(Self.boardKey)/task/\(Self.targetULID.lowercased())"
        let markers = DependencyMarkers.all(in: body)
        #expect(markers.map(\.uri) == [try Self.uri(ofTask: Self.targetULID)])
    }

    @Test("A task URL with more segments after the ULID is not a marker")
    func longerURLIsNotMarker() {
        let body = "\(Self.url(ofTask: Self.targetULID))/comment/\(Self.missingULID)"
        #expect(DependencyMarkers.all(in: body).isEmpty)
    }

    // MARK: - Remove

    @Test("A remove takes each URL of one task out of the body, and keeps the other URLs and lines")
    func removeTakesOutOneTask() throws {
        let target = Self.url(ofTask: Self.targetULID)
        let other = Self.url(ofTask: Self.missingULID, inBoard: Self.otherBoardKey)
        let body = "Wait for \(target) and \(other).\nKeep this line.  \nAgain \(target)\n"
        let expected = "Wait for  and \(other).\nKeep this line.  \nAgain\n"
        #expect(DependencyMarkers.removing(markersOf: try Self.uri(ofTask: Self.targetULID), from: body) == expected)
    }

    @Test("A remove that empties the last line, which has no newline, also removes the newline before it")
    func removeOfLastLineRemovesItsNewline() throws {
        let body = "Title line\r\n\(Self.url(ofTask: Self.targetULID))"
        let result = DependencyMarkers.removing(markersOf: try Self.uri(ofTask: Self.targetULID), from: body)
        #expect(result == "Title line")
    }

    @Test("A remove of a task that the body does not name gives the same body")
    func removeOfUnknownTaskKeepsBody() throws {
        let body = "Line one  \r\nLine two \(Self.url(ofTask: Self.targetULID))\n"
        let result = DependencyMarkers.removing(markersOf: try Self.uri(ofTask: Self.missingULID), from: body)
        #expect(result == body)
    }
}
