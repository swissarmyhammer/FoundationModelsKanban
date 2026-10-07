import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the local ref of a node and the stored ref, the two forms that the log holds (plan.md §3.2, §12 item 18).
@Suite("Local refs")
struct LocalRefTests {
    /// The ULID text of the test task.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of the test comment.
    static let commentULID = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The board key of the current board.
    static let currentKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The board key of a different board.
    static let otherKey = "github.com/swissarmyhammer/swissarmyhammer"

    /// The local ref text of each of the six node types.
    static let refTexts = [
        "board",
        "column/doing",
        "actor/claude-code",
        "task/\(taskULID)",
        "tag/bug",
        "comment/\(commentULID)",
    ]

    // MARK: - Parse and format

    @Test("Each node type round-trips from text to a local ref and back", arguments: refTexts)
    func refRoundTrips(text: String) throws {
        #expect(try LocalRef(parsing: text).description == text)
    }

    @Test("A task ref holds the ULID and the task type")
    func taskRefHoldsULID() throws {
        let ulid = try #require(ULID(ulidString: Self.taskULID))
        let ref = try LocalRef(parsing: "task/\(Self.taskULID)")
        #expect(ref == .task(ulid))
        #expect(ref.nodeType == .task)
    }

    @Test("Each ref gives its node type")
    func refsGiveNodeTypes() throws {
        let types = try Self.refTexts.map { try LocalRef(parsing: $0).nodeType }
        #expect(types == [.board, .column, .actor, .task, .tag, .comment])
    }

    @Test("A slug ref holds the slug as written")
    func slugRefHoldsSlug() throws {
        #expect(try LocalRef(parsing: "column/doing") == .column(slug: "doing"))
        #expect(try LocalRef(parsing: "actor/claude-code") == .actor(slug: "claude-code"))
        #expect(try LocalRef(parsing: "tag/bug") == .tag(slug: "bug"))
    }

    @Test("The type segment ignores case, and the ref text uses lowercase")
    func typeSegmentIgnoresCase() throws {
        #expect(try LocalRef(parsing: "Task/\(Self.taskULID)").description == "task/\(Self.taskULID)")
        #expect(try LocalRef(parsing: "BOARD") == .board)
    }

    @Test("A ULID in lowercase gives the ULID in uppercase")
    func lowercaseULIDIsCanonical() throws {
        let ref = try LocalRef(parsing: "comment/\(Self.commentULID.lowercased())")
        #expect(ref.description == "comment/\(Self.commentULID)")
    }

    // MARK: - Malformed refs

    @Test(
        "A ref with no known type, or the wrong number of segments, is an invalid local ref",
        arguments: ["", "widget/x", "column", "column/", "column/a/b", "board/x", "/doing"]
    )
    func malformedRefThrows(text: String) {
        #expect(throws: NodeRefError.invalidLocalRef(ref: text)) {
            try LocalRef(parsing: text)
        }
    }

    @Test(
        "A task or comment ref whose id is not a ULID is an invalid ULID",
        arguments: ["task/abc", "comment/^ajv8v4t"]
    )
    func nonULIDThrows(text: String) {
        #expect(throws: NodeRefError.invalidULID(ref: text)) {
            try LocalRef(parsing: text)
        }
    }

    // MARK: - Stored refs

    @Test("A stored text with no scheme is a local ref")
    func storedTextWithoutSchemeIsLocal() throws {
        let stored = try StoredRef(parsing: "tag/bug")
        #expect(stored == .local(.tag(slug: "bug")))
        #expect(stored.description == "tag/bug")
    }

    @Test("A stored text with the scheme is a remote ref")
    func storedTextWithSchemeIsRemote() throws {
        let text = "kanban://\(Self.otherKey)/task/\(Self.taskULID)"
        let stored = try StoredRef(parsing: text)
        #expect(stored == .remote(try NodeURI(parsing: text)))
        #expect(stored.description == text)
    }

    @Test("A stored text with the scheme in uppercase is a remote ref")
    func storedTextWithUppercaseSchemeIsRemote() throws {
        let stored = try StoredRef(parsing: "KANBAN://\(Self.otherKey)/board")
        #expect(stored == .remote(NodeURI(boardKey: Self.otherKey, ref: .board)))
    }

    @Test("A malformed stored text gives the error of its form")
    func malformedStoredTextThrows() {
        #expect(throws: NodeRefError.invalidLocalRef(ref: "widget/x")) {
            try StoredRef(parsing: "widget/x")
        }
        #expect(throws: NodeRefError.invalidBoardKey(uri: "kanban://board")) {
            try StoredRef(parsing: "kanban://board")
        }
    }

    @Test("A URI with the current key is stored as a local ref")
    func uriWithCurrentKeyIsLocal() {
        let uri = NodeURI(boardKey: Self.currentKey, ref: .column(slug: "doing"))
        #expect(StoredRef(uri: uri, inBoard: Self.currentKey) == .local(.column(slug: "doing")))
    }

    @Test("A URI with a different key is stored as a remote ref")
    func uriWithDifferentKeyIsRemote() {
        let uri = NodeURI(boardKey: Self.otherKey, ref: .column(slug: "doing"))
        #expect(StoredRef(uri: uri, inBoard: Self.currentKey) == .remote(uri))
    }

    @Test("A local stored ref gives a URI with the current key")
    func localStoredRefGivesCurrentKey() {
        let stored = StoredRef.local(.tag(slug: "bug"))
        #expect(stored.uri(inBoard: Self.currentKey) == NodeURI(boardKey: Self.currentKey, ref: .tag(slug: "bug")))
    }

    @Test("A remote stored ref keeps its own key")
    func remoteStoredRefKeepsItsKey() {
        let uri = NodeURI(boardKey: Self.otherKey, ref: .board)
        #expect(StoredRef.remote(uri).uri(inBoard: Self.currentKey) == uri)
    }

    @Test("Each node type round-trips from a stored ref to a URI and back", arguments: refTexts)
    func storedRefRoundTripsThroughURI(text: String) throws {
        let stored = try StoredRef(parsing: text)
        let uri = stored.uri(inBoard: Self.currentKey)
        #expect(StoredRef(uri: uri, inBoard: Self.currentKey) == stored)
    }
}
