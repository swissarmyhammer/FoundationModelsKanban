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

    /// The key ``currentKey`` with its host in mixed case.
    static let mixedCaseKey = "GitHub.COM/swissarmyhammer/FoundationModelsKanban"

    /// The start of a board key before the repo name: the host and the owner of a remote, and the host of a repo
    /// with no remote.
    static let keyPrefixes = ["github.com/acme", BoardKey.localHost]

    /// The name of each node type other than the board. A board URI test uses each name as the name of a repo.
    static let typeNames = PatchNodeType.allCases.filter { type in type != .board }.map(\.pathSegment)

    /// The board keys of the ref round-trip test: the current key, and each key whose repo name is a node type.
    static let roundTripKeys = [currentKey] + keyPrefixes.flatMap { prefix in typeNames.map { "\(prefix)/\($0)" } }

    /// The ULID text of the test task.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of the test comment.
    static let commentULID = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The slug of the test actor.
    static let actorSlug = "claude-code"

    /// The full URI of each of the six node types in the current board.
    static let uriTexts = [
        "kanban://\(currentKey)/board",
        "kanban://\(currentKey)/column/doing",
        "kanban://\(currentKey)/actor/\(actorSlug)",
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

    @Test(
        "Each node type with a legal slug round-trips from a ref to a URI, also in a repo named for a node type",
        arguments: uriTexts, roundTripKeys
    )
    func refRoundTripsThroughURI(text: String, key: String) throws {
        let uri = NodeURI(boardKey: key, ref: try NodeURI(parsing: text).ref)
        #expect(try NodeURI(parsing: uri.description) == uri)
    }

    @Test("A column, an actor, or a tag with the reserved slug gives a URI that parses as the board URI")
    func reservedSlugURIParsesAsBoard() throws {
        let refs: [LocalRef] = [
            .column(slug: Slug.reservedForBoard),
            .actor(slug: Slug.reservedForBoard),
            .tag(slug: Slug.reservedForBoard),
        ]
        for ref in refs {
            let uri = NodeURI(boardKey: Self.currentKey, ref: ref)
            #expect(try NodeURI(parsing: uri.description).ref == .board)
        }
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

    @Test(
        "A board URI whose repo name is a node type is the board URI with the full key",
        arguments: keyPrefixes, typeNames
    )
    func boardURIOfTypeNamedRepo(prefix: String, typeName: String) throws {
        let key = "\(prefix)/\(typeName)"
        let uri = try NodeURI(parsing: "kanban://\(key)/board")
        #expect(uri == NodeURI(boardKey: key, ref: .board))
    }

    @Test("The parse makes the host of the key lowercase with the rule of a remote key, and the path keeps its case")
    func parseMakesHostLowercase() throws {
        let uri = try NodeURI(parsing: "kanban://\(Self.mixedCaseKey)/task/\(Self.taskULID)")
        #expect(uri.boardKey == Self.currentKey)
        #expect(uri.boardKey == (try BoardKey(remoteURL: "https://\(Self.mixedCaseKey)")).description)
    }

    @Test("A URI whose host differs from the current key only in case gives its local ref")
    func mixedCaseHostGivesLocalRef() throws {
        let uri = try NodeURI(parsing: "kanban://\(Self.mixedCaseKey)/actor/\(Self.actorSlug)")
        #expect(uri.localRef(inBoard: Self.currentKey) == .actor(slug: Self.actorSlug))
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
        let uri = NodeURI(boardKey: Self.currentKey, ref: .actor(slug: Self.actorSlug))
        #expect(uri.localRef(inBoard: Self.currentKey) == .actor(slug: Self.actorSlug))
    }

    @Test("A URI with a different key gives no local ref")
    func uriInOtherBoardGivesNoLocalRef() {
        let uri = NodeURI(boardKey: Self.otherKey, ref: .actor(slug: Self.actorSlug))
        #expect(uri.localRef(inBoard: Self.currentKey) == nil)
    }
}
