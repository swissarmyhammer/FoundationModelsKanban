import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the parse and the format of the full URI of a node, and the change between a URI and a local ref with the
/// current board key (plan.md §3.2, §12 item 18).
@Suite("Node URIs")
struct NodeURITests {
    /// The board key of the current board. It has slashes, as a key from a git remote has.
    static let currentKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The board key of a different board.
    static let otherKey = "github.com/swissarmyhammer/swissarmyhammer"

    /// The ULID text of the test task.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of the test comment.
    static let commentULID = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The full URI of each of the six node types in the current board.
    static let uriTexts = [
        "kanban://\(currentKey)/board",
        "kanban://\(currentKey)/column/doing",
        "kanban://\(currentKey)/actor/claude-code",
        "kanban://\(currentKey)/task/\(taskULID)",
        "kanban://\(currentKey)/tag/bug",
        "kanban://\(currentKey)/comment/\(commentULID)",
    ]

    // MARK: - Round trip

    @Test("Each node type round-trips from a URI to a local ref and back to the URI", arguments: uriTexts)
    func uriRoundTripsThroughLocalRef(text: String) throws {
        let uri = try NodeURI(parsing: text)
        let ref = try #require(uri.localRef(inBoard: Self.currentKey))
        #expect(NodeURI(boardKey: Self.currentKey, ref: ref).description == text)
    }

    // MARK: - Parse

    @Test("The parse finds the board key and the local ref of a task")
    func parseFindsKeyAndRef() throws {
        let ulid = try #require(ULID(ulidString: Self.taskULID))
        let uri = try NodeURI(parsing: "kanban://\(Self.currentKey)/task/\(Self.taskULID)")
        #expect(uri.boardKey == Self.currentKey)
        #expect(uri.ref == .task(ulid))
    }

    @Test("The parse finds the board key of the board URI")
    func parseFindsKeyOfBoard() throws {
        let uri = try NodeURI(parsing: "kanban://\(Self.currentKey)/board")
        #expect(uri == NodeURI(boardKey: Self.currentKey, ref: .board))
    }

    @Test("A key of a repo with no remote has two segments")
    func parseFindsLocalKey() throws {
        let uri = try NodeURI(parsing: "kanban://local/my-repo/tag/bug")
        #expect(uri == NodeURI(boardKey: "local/my-repo", ref: .tag(slug: "bug")))
    }

    @Test("A column with the slug board is a column, not the board")
    func columnNamedBoardIsColumn() throws {
        let uri = try NodeURI(parsing: "kanban://\(Self.currentKey)/column/board")
        #expect(uri == NodeURI(boardKey: Self.currentKey, ref: .column(slug: "board")))
    }

    @Test("The scheme and the type segment ignore case")
    func schemeAndTypeIgnoreCase() throws {
        let uri = try NodeURI(parsing: "KANBAN://\(Self.currentKey)/Column/doing")
        #expect(uri.description == "kanban://\(Self.currentKey)/column/doing")
    }

    @Test("The scheme check finds the scheme at the start of a text, and ignores case")
    func schemeCheckFindsSchemeAtStart() {
        #expect(NodeURI.hasScheme(atStartOf: "kanban://\(Self.currentKey)/board"))
        #expect(NodeURI.hasScheme(atStartOf: "KANBAN://\(Self.currentKey)/board"))
        #expect(!NodeURI.hasScheme(atStartOf: "tag/kanban://"))
        #expect(!NodeURI.hasScheme(atStartOf: ""))
    }

    // MARK: - Malformed URIs

    @Test(
        "A text without the scheme is a missing scheme",
        arguments: ["column/doing", "https://\(currentKey)/column/doing", "kanban:/\(currentKey)/board", ""]
    )
    func textWithoutSchemeThrows(text: String) {
        #expect(throws: NodeRefError.missingScheme(uri: text)) {
            try NodeURI(parsing: text)
        }
    }

    @Test(
        "A URI with no board key, or with an empty key segment, is an invalid board key",
        arguments: [
            "kanban://",
            "kanban://board",
            "kanban://task/\(taskULID)",
            "kanban:///column/doing",
            "kanban://github.com//repo/board",
        ]
    )
    func uriWithoutKeyThrows(text: String) {
        #expect(throws: NodeRefError.invalidBoardKey(uri: text)) {
            try NodeURI(parsing: text)
        }
    }

    @Test("A URI whose end is not a local ref is an invalid local ref")
    func uriWithUnknownTypeThrows() {
        #expect(throws: NodeRefError.invalidLocalRef(ref: "widget/x")) {
            try NodeURI(parsing: "kanban://\(Self.currentKey)/widget/x")
        }
        #expect(throws: NodeRefError.invalidLocalRef(ref: "column/")) {
            try NodeURI(parsing: "kanban://\(Self.currentKey)/column/")
        }
    }

    @Test("A task URI whose id is not a ULID is an invalid ULID")
    func taskURIWithoutULIDThrows() {
        #expect(throws: NodeRefError.invalidULID(ref: "task/ajv8v4t")) {
            try NodeURI(parsing: "kanban://\(Self.currentKey)/task/ajv8v4t")
        }
    }

    // MARK: - Local ref in a board

    @Test("A URI with the current key gives its local ref")
    func uriInCurrentBoardGivesLocalRef() {
        let uri = NodeURI(boardKey: Self.currentKey, ref: .actor(slug: "claude-code"))
        #expect(uri.localRef(inBoard: Self.currentKey) == .actor(slug: "claude-code"))
    }

    @Test("A URI with a different key gives no local ref")
    func uriInOtherBoardGivesNoLocalRef() {
        let uri = NodeURI(boardKey: Self.otherKey, ref: .actor(slug: "claude-code"))
        #expect(uri.localRef(inBoard: Self.currentKey) == nil)
    }
}
