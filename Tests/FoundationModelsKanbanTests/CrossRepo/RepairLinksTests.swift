import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Mutation.repairLinks` (divergence.md M9): the rewrite of each link with an old board name to the current
/// name of the board, in each link field (`dependsOn`, an assignee URI, a task URL in a body, the line of a moved
/// task), one `undo` of the rewrite, `dryRun`, the boards that the call writes to, and a dangling link.
///
/// Each test makes real git repos in a ``GitSandbox``. The engines read the worktree tops and the board keys from git.
@Suite("repairLinks", .watcherBudget)
struct RepairLinksTests {
    /// The selection of each link of `Mutation.repairLinks`.
    static let repairSelection = "{ board node field target status currentName newTarget }"

    // MARK: - Helpers

    /// One link of a `Mutation.repairLinks` response.
    struct Repair: Equatable {
        /// The link and its class before the rewrite.
        let check: CheckLinksTests.Check

        /// The link after the rewrite, or `nil` when the call does not change the link.
        let newTarget: String?

        /// Reads one link of a response.
        ///
        /// - Parameter object: The link object of the response.
        /// - Throws: An error when a field that is not nullable has no text.
        init(_ object: [String: Any]) throws {
            check = try CheckLinksTests.Check(object)
            newTarget = object["newTarget"] as? String
        }

        /// Makes the expected value of one link.
        ///
        /// - Parameters:
        ///   - check: The link and its class before the rewrite.
        ///   - newTarget: The link after the rewrite, or `nil` for no change.
        init(check: CheckLinksTests.Check, newTarget: String?) {
            self.check = check
            self.newTarget = newTarget
        }
    }

    /// Runs `Mutation.repairLinks`, and expects that the response has no error.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the field, for example `(dryRun: true)`, or the empty text.
    ///   - graph: The engine.
    /// - Returns: The links of the response, and the response JSON text.
    /// - Throws: An error when the response has no list of links.
    static func repairs(
        with arguments: String = "",
        on graph: KanbanGraph
    ) async throws -> (repairs: [Repair], response: String) {
        let field = "\(MutationName.repairLinks)\(arguments) \(repairSelection)"
        let response = try await CrossRepoUndoTests.runWithNoErrors(field, on: graph)
        let objects = try #require(
            KanbanGraphTests.data(of: response)[MutationName.repairLinks] as? [[String: Any]],
            "\(response)"
        )
        return (try objects.map(Repair.init), response)
    }

    /// Gives a node URI with a different board key.
    ///
    /// - Parameters:
    ///   - uri: The full URI of a node.
    ///   - key: The new board key.
    /// - Returns: The full URI of the same node with the new key.
    /// - Throws: An error when the text is not a node URI.
    static func uri(_ uri: String, withKey key: String) throws -> String {
        NodeURI(boardKey: key, ref: try NodeURI(parsing: uri).ref).description
    }

    /// Gives a checked link with a different target and class.
    ///
    /// - Parameters:
    ///   - check: The checked link.
    ///   - target: The new target.
    ///   - status: The new class.
    /// - Returns: The checked link with the target and the class.
    static func check(_ check: CheckLinksTests.Check, target: String, status: String) -> CheckLinksTests.Check {
        CheckLinksTests.Check(
            board: check.board,
            node: check.node,
            field: check.field,
            target: target,
            status: status,
            currentName: check.currentName
        )
    }

    /// Runs `repairLinks` on a board whose links have one old board name, and expects that the call rewrites each
    /// link to the current name: the response lists each link with its new target, and `checkLinks` then gives `OK`
    /// and the new target for each link.
    ///
    /// - Parameters:
    ///   - graph: The engine of the board that holds the links.
    ///   - newKey: The current key of the board that the links name.
    /// - Throws: An error when a call fails.
    static func expectRepair(on graph: KanbanGraph, toKey newKey: String) async throws {
        let before = try await CheckLinksTests.checks(on: graph)
        let statuses = Set(before.checks.map(\.status))
        #expect(statuses == [LinkStatus.oldName.rawValue], "\(before.response)")
        let result = try await repairs(on: graph)
        let expected = try before.checks.map { link in
            Repair(check: link, newTarget: try uri(link.target, withKey: newKey))
        }
        #expect(result.repairs == expected, "\(result.response)")
        let after = try await CheckLinksTests.checks(on: graph)
        let repaired = try before.checks.map { link in
            check(link, target: try uri(link.target, withKey: newKey), status: LinkStatus.ok.rawValue)
        }
        #expect(after.checks == repaired, "\(after.response)")
    }

    // MARK: - Link fields

    @Test("repairLinks rewrites a dependsOn link with an old board name to the current name")
    func repairsDependsOn() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(completingTarget: false)
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        try await Self.expectRepair(on: app, toKey: renamed.newKey)
        await app.close()
    }

    @Test("repairLinks rewrites a task URL in a body with an old board name to the current name")
    func repairsBodyURL() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(
            completingTarget: false,
            linkingWith: CheckLinksTests.bodyInput
        )
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        try await Self.expectRepair(on: app, toKey: renamed.newKey)
        let body = try await CrossRepoTransferTests.task(renamed.task, selecting: "{ body }", on: app)["body"]
        await app.close()
        let newTarget = try Self.uri(renamed.target, withKey: renamed.newKey)
        #expect(body as? String == "Needs \(newTarget) first.")
    }

    @Test("repairLinks rewrites the line of a moved task with an old board name to the current name")
    func repairsMovedLine() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await CheckLinksTests.moveNewTaskToLib(on: app)
        await app.close()
        try await BoardIDTests.setNewRemote(ofRepoAt: repos.lib)
        let reopened = try GitGraphFixture.makeGraph(at: repos.app)
        try await Self.expectRepair(on: reopened, toKey: try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin))
        await reopened.close()
    }

    @Test("repairLinks rewrites an assignee URI with an old board name to the current name")
    func repairsAssignee() async throws {
        let transfer = try await CrossRepoTransferTests.makeAssignedTransfer(MutationName.moveTask)
        try await BoardIDTests.setNewRemote(ofRepoAt: transfer.repos.app)
        let lib = try CrossRepoTransferTests.makeLibGraph(in: transfer.repos)
        try await Self.expectRepair(on: lib, toKey: try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin))
        await lib.close()
    }

    // MARK: - Undo and dry run

    @Test("One undo puts back each link that repairLinks rewrote")
    func undoPutsBackEachLink() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(completingTarget: false) { target in
            CrossRepoFixture.dependsOnInput(target) + ", " + CheckLinksTests.bodyInput(target)
        }
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        let before = try await CheckLinksTests.checks(on: app)
        let repaired = try await Self.repairs(on: app)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: app)
        let after = try await CheckLinksTests.checks(on: app)
        await app.close()
        let fields = [LinkField.dependsOn, LinkField.body].map(\.rawValue)
        #expect(before.checks.map(\.field) == fields, "\(before.response)")
        let newTarget = try Self.uri(renamed.target, withKey: renamed.newKey)
        #expect(repaired.repairs.map(\.newTarget) == [newTarget, newTarget], "\(repaired.response)")
        #expect(after.checks == before.checks, "\(after.response)")
    }

    @Test("repairLinks(dryRun: true) writes nothing, and lists the same changes as the call that writes")
    func dryRunWritesNothing() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(completingTarget: false)
        let app = try GitGraphFixture.makeGraph(at: renamed.repos.app)
        let before = try await CheckLinksTests.checks(on: app)
        let dryRun = try await Self.repairs(with: "(dryRun: true)", on: app)
        let afterDryRun = try await CheckLinksTests.checks(on: app)
        let written = try await Self.repairs(on: app)
        await app.close()
        #expect(afterDryRun.checks == before.checks, "\(afterDryRun.response)")
        #expect(!dryRun.repairs.isEmpty && dryRun.repairs == written.repairs, "\(dryRun.response)")
    }

    // MARK: - Boards of the call

    @Test("repairLinks does not change a board that the call does not name, and reach: true changes it")
    func reachWritesToReachableBoards() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(completingTarget: false)
        let lib = try CrossRepoTransferTests.makeLibGraph(in: renamed.repos)
        let appBoard = #"(boards: ["\#(BoardLocatorTests.appName)"])"#
        let named = try await Self.repairs(on: lib)
        let afterNamed = try await CheckLinksTests.checks(with: appBoard, on: lib)
        let reached = try await Self.repairs(with: "(reach: true)", on: lib)
        let afterReach = try await CheckLinksTests.checks(with: appBoard, on: lib)
        await lib.close()
        #expect(named.repairs.isEmpty, "\(named.response)")
        #expect(afterNamed.checks.map(\.status) == [LinkStatus.oldName.rawValue], "\(afterNamed.response)")
        let newTarget = try Self.uri(renamed.target, withKey: renamed.newKey)
        #expect(reached.repairs.map(\.newTarget) == [newTarget], "\(reached.response)")
        #expect(afterReach.checks.map(\.target) == [newTarget], "\(afterReach.response)")
    }

    @Test("repairLinks accepts the forgiving names board, reachable, and preview")
    func forgivingArgumentNames() async throws {
        let renamed = try await CheckLinksTests.makeRenamedLib(completingTarget: false)
        let lib = try CrossRepoTransferTests.makeLibGraph(in: renamed.repos)
        let arguments = #"(board: "\#(BoardLocatorTests.appName)", reachable: false, preview: true)"#
        let result = try await Self.repairs(with: arguments, on: lib)
        let after = try await CheckLinksTests.checks(with: #"(board: "\#(BoardLocatorTests.appName)")"#, on: lib)
        await lib.close()
        let newTarget = try Self.uri(renamed.target, withKey: renamed.newKey)
        #expect(result.repairs.map(\.newTarget) == [newTarget], "\(result.response)")
        #expect(after.checks.map(\.status) == [LinkStatus.oldName.rawValue], "\(after.response)")
    }

    // MARK: - Dangling links

    @Test("repairLinks reports a dangling link with no new target, and does not change it")
    func danglingLinkIsReportedOnly() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        _ = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let before = try await CheckLinksTests.checks(on: app)
        let result = try await Self.repairs(on: app)
        let after = try await CheckLinksTests.checks(on: app)
        await app.close()
        let expected = before.checks.map { link in Repair(check: link, newTarget: nil) }
        #expect(before.checks.map(\.status) == [LinkStatus.dangling.rawValue], "\(before.response)")
        #expect(result.repairs == expected, "\(result.response)")
        #expect(after.checks == before.checks, "\(after.response)")
    }

    // MARK: - Units

    @Test("The body rewrite changes each task URL of the old URI, and keeps a URL in a code block")
    func bodyRewriteKeepsCodeBlock() throws {
        let old = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID()))
        let new = NodeURI(boardKey: try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin), ref: old.ref)
        let body = "See \(old) and \(old).\n```\n\(old)\n```\n"
        let expected = "See \(new) and \(new).\n```\n\(old)\n```\n"
        #expect(DependencyMarkers.replacing(markersOf: old, with: new, in: body) == expected)
    }

    @Test("The moved line rewrite keeps the line break of the line, also CRLF, and each other line")
    func movedLineRewriteKeepsLineBreak() throws {
        let old = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID()))
        let new = NodeURI(boardKey: try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin), ref: old.ref)
        let body = "Notes.\r\n\r\n\(MovedTaskLine.text(pointingTo: old))\r\nMoved to the next sprint."
        let expected = "Notes.\r\n\r\n\(MovedTaskLine.text(pointingTo: new))\r\nMoved to the next sprint."
        #expect(MovedTaskLine.replacing(old, with: new, in: body) == expected)
    }
}
