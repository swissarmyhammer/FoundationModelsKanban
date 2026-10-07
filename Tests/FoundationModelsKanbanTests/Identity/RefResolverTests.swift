import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the change of a forgiving ref to a stored ref (plan.md §3.2, §4.4).
///
/// The task cases are a port of the short id and `^` cases of the Rust file
/// `swissarmyhammer-kanban/src/dispatch/tests/short_ids.rs`. One case is different: the Rust resolver returns a full
/// ULID that is not on the board with no check. This resolver gives `NOT_FOUND` for each node that the board does
/// not have.
@Suite("Ref resolver")
struct RefResolverTests {
    /// The ULID text of the task that most tests resolve: the third task of the fixture.
    static let target = ReadinessFixture.third

    /// The short id of the target task: the last seven characters of its ULID, in lowercase.
    static let targetShortID = "jraj9vg"

    /// The ULID text of the tombstoned task of the board.
    static let deleted = ReadinessFixture.fourth

    /// A prefix of the first and the second task. No other live task starts with it.
    static let sharedPrefix = "01KT6R"

    /// A ULID whose short id is `01kt6r7`: a prefix of the ULID of the second task.
    static let collidingULID = "01KT6R6HR3KJT6JVNDR01KT6R7"

    /// The slug of a tag that a rename made point to ``renameTarget``.
    static let renamedTag = "bug"

    /// The slug of the live tag at the end of the rename of ``renamedTag``.
    static let renameTarget = "defect"

    /// The slug of a tag that a rename made point to the tombstone ``retiredTag``.
    static let staleTag = "stale"

    /// The slug of a tombstoned tag.
    static let retiredTag = "retired"

    /// The slug of a tag whose name has a space: `Bug Fix`.
    static let spacedTag = "bug-fix"

    /// Gives the test board: the default columns, one actor, four tasks (the fourth is a tombstone), one comment,
    /// and the tags of the rename tests.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a ULID text of the fixture is not valid.
    static func board() throws -> ReadinessFixture {
        var board = ReadinessFixture()
        board.graph.update(with: .board(BoardNode(fields: ReadinessFixture.fields())))
        board.addActor(withSlug: ReadinessFixture.author)
        for text in [ReadinessFixture.first, ReadinessFixture.second, target] {
            try board.addTask(withULID: text)
        }
        try board.addTask(withULID: deleted, fields: ReadinessFixture.fields(isDeleted: true))
        try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        addTag(withSlug: renamedTag, renamedTo: renameTarget, to: &board)
        addTag(withSlug: renameTarget, to: &board)
        addTag(withSlug: staleTag, renamedTo: retiredTag, to: &board)
        addTag(withSlug: retiredTag, isDeleted: true, to: &board)
        addTag(withSlug: spacedTag, to: &board)
        return board
    }

    /// Adds a tag to a board.
    ///
    /// - Parameters:
    ///   - slug: The slug of the tag.
    ///   - target: The slug of the tag that a rename made this tag point to, or `nil`.
    ///   - isDeleted: `true` when the tag is a tombstone.
    ///   - board: The board that gets the tag.
    static func addTag(
        withSlug slug: String,
        renamedTo target: String? = nil,
        isDeleted: Bool = false,
        to board: inout ReadinessFixture
    ) {
        let edge = target.map { slug in EdgeTarget.unresolved(.local(.tag(slug: slug))) }
        let tag = TagNode(slug: slug, fields: ReadinessFixture.fields(isDeleted: isDeleted), renamedTo: edge)
        board.graph.update(with: .tag(tag))
    }

    /// Resolves a ref in the test board.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it.
    ///   - type: The expected node type.
    ///   - acceptsRemote: `true` when the caller accepts a ref to a node of a different board.
    ///   - includesTombstones: `true` when the ref can name a tombstone.
    ///   - board: The board, or `nil` for the test board of ``board()``.
    /// - Returns: The stored ref.
    /// - Throws: The ``KanbanError`` of the resolve, or an error when a ULID text of the fixture is not valid.
    static func resolve(
        _ reference: String,
        as type: PatchNodeType,
        acceptingRemote acceptsRemote: Bool = false,
        includingTombstones includesTombstones: Bool = false,
        in board: ReadinessFixture? = nil
    ) throws -> StoredRef {
        let graph = try (board ?? Self.board()).graph
        let resolver = RefResolver(graph: graph, boardKey: DependencyMarkersTests.boardKey)
        return try resolver.storedRef(
            for: reference,
            ofType: type,
            acceptingRemote: acceptsRemote,
            includingTombstones: includesTombstones
        )
    }

    /// Gives the stored ref of a task of the board.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The local ref of the task.
    /// - Throws: An error when the text is not a ULID.
    static func storedRef(ofTask text: String) throws -> StoredRef {
        .local(.task(try DependencyMarkersTests.ulid(of: text)))
    }

    /// Gives the `NOT_FOUND` error of a ref.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it.
    ///   - type: The expected node type.
    /// - Returns: The error.
    static func notFound(_ reference: String, as type: PatchNodeType) -> KanbanError {
        .notFound(type: type, reference: reference)
    }

    // MARK: - Short forms

    @Test(
        "Each short form of a task resolves to the same task",
        arguments: [
            target,
            target.lowercased(),
            "\(ShortID.sigil)\(target)",
            "\(ShortID.sigil)\(target.lowercased())",
            targetShortID,
            "\(ShortID.sigil)\(targetShortID)",
            targetShortID.uppercased(),
            "\(ShortID.sigil)\(targetShortID.uppercased())",
            "01kt6s",
            " \(targetShortID) ",
            DependencyMarkersTests.url(ofTask: target),
        ]
    )
    func shortFormResolvesToTask(reference: String) throws {
        #expect(try Self.resolve(reference, as: .task) == Self.storedRef(ofTask: Self.target))
    }

    @Test("A short id resolves to a comment")
    func shortIDResolvesToComment() throws {
        let comment = ReadinessFixture.firstComment
        let expected = StoredRef.local(.comment(try DependencyMarkersTests.ulid(of: comment)))
        #expect(try Self.resolve(ShortID(ofULIDString: comment).value, as: .comment) == expected)
    }

    @Test("A task ref does not resolve to a comment, and a comment ref does not resolve to a task")
    func ulidTypesStaySeparate() {
        let comment = ReadinessFixture.firstComment
        #expect(throws: Self.notFound(comment, as: .task)) {
            try Self.resolve(comment, as: .task)
        }
        #expect(throws: Self.notFound(Self.target, as: .comment)) {
            try Self.resolve(Self.target, as: .comment)
        }
    }

    @Test("A canonical short id wins over a prefix of a different task")
    func canonicalShortIDWinsOverPrefix() throws {
        var board = try Self.board()
        try board.addTask(withULID: Self.collidingULID)
        let shortID = ShortID(ofULIDString: Self.collidingULID).value
        #expect(try Self.resolve(shortID, as: .task, in: board) == Self.storedRef(ofTask: Self.collidingULID))
    }

    // MARK: - Ambiguous and not found

    @Test("A prefix of more than one task gives AMBIGUOUS_ID with the short ids of the matches")
    func ambiguousPrefixGivesMatches() {
        let matches = [ReadinessFixture.first, ReadinessFixture.second].map(ShortID.init(ofULIDString:))
        #expect(throws: KanbanError.ambiguousID(reference: Self.sharedPrefix, matches: matches)) {
            try Self.resolve(Self.sharedPrefix, as: .task)
        }
    }

    @Test("A tombstone is not a match of an ambiguous prefix")
    func tombstoneIsNotAmbiguousMatch() {
        let live = [ReadinessFixture.first, ReadinessFixture.second, Self.target]
        let error = KanbanError.ambiguousID(reference: "01KT6", matches: live.map(ShortID.init(ofULIDString:)))
        #expect(throws: error) {
            try Self.resolve("01KT6", as: .task)
        }
    }

    @Test(
        "A ref to a task that the board does not have gives NOT_FOUND",
        arguments: ["zzzzzzz", "nosuch7", ReadinessFixture.ghost, "", ShortID.sigil.description]
    )
    func unknownTaskGivesNotFound(reference: String) {
        #expect(throws: Self.notFound(reference, as: .task)) {
            try Self.resolve(reference, as: .task)
        }
    }

    // MARK: - Tombstones

    @Test("A ref to a tombstone gives NOT_FOUND, unless the caller asks for tombstones")
    func tombstoneNeedsTheOption() throws {
        let shortID = ShortID(ofULIDString: Self.deleted).value
        #expect(throws: Self.notFound(shortID, as: .task)) {
            try Self.resolve(shortID, as: .task)
        }
        let resolved = try Self.resolve(shortID, as: .task, includingTombstones: true)
        #expect(resolved == (try Self.storedRef(ofTask: Self.deleted)))
    }

    // MARK: - Slugs and tag names

    @Test("A column name and an actor name resolve by their slugs")
    func namesResolveBySlug() throws {
        #expect(try Self.resolve("Doing", as: .column) == .local(.column(slug: ReadinessFixture.doing)))
        #expect(try Self.resolve("Claude Code", as: .actor) == .local(.actor(slug: ReadinessFixture.author)))
    }

    @Test("A column that the board does not have gives NOT_FOUND")
    func unknownColumnGivesNotFound() {
        #expect(throws: Self.notFound("backlog", as: .column)) {
            try Self.resolve("backlog", as: .column)
        }
    }

    @Test("A tag name is normalized to its slug", arguments: ["Bug Fix", "#bug-fix", "BUG_FIX"])
    func tagNameResolvesBySlug(reference: String) throws {
        #expect(try Self.resolve(reference, as: .tag) == .local(.tag(slug: Self.spacedTag)))
    }

    @Test("A tag ref follows the rename redirect")
    func tagRefFollowsRedirect() throws {
        #expect(try Self.resolve("Bug", as: .tag) == .local(.tag(slug: Self.renameTarget)))
    }

    @Test("A tag ref whose redirect ends at a tombstone gives NOT_FOUND, unless the caller asks for tombstones")
    func tagRedirectToTombstone() throws {
        #expect(throws: Self.notFound(Self.staleTag, as: .tag)) {
            try Self.resolve(Self.staleTag, as: .tag)
        }
        let resolved = try Self.resolve(Self.staleTag, as: .tag, includingTombstones: true)
        #expect(resolved == .local(.tag(slug: Self.retiredTag)))
    }

    @Test("A tag name that gives an empty slug gives NOT_FOUND")
    func emptyTagSlugGivesNotFound() {
        #expect(throws: Self.notFound("###", as: .tag)) {
            try Self.resolve("###", as: .tag)
        }
    }

    // MARK: - URIs and the board

    @Test("A URI with the current key gives a local ref, and its slug is normalized")
    func currentURIGivesLocalRef() throws {
        let uri = "\(NodeURI.scheme)\(DependencyMarkersTests.boardKey)/tag/Bug"
        #expect(try Self.resolve(uri, as: .tag) == .local(.tag(slug: Self.renameTarget)))
    }

    @Test("A URI with a different key gives a remote ref when the caller accepts cross-board refs")
    func otherURIGivesRemoteRef() throws {
        let key = DependencyMarkersTests.otherBoardKey
        let text = DependencyMarkersTests.url(ofTask: ReadinessFixture.ghost, inBoard: key)
        let expected = StoredRef.remote(try DependencyMarkersTests.uri(ofTask: ReadinessFixture.ghost, inBoard: key))
        #expect(try Self.resolve(text, as: .task, acceptingRemote: true) == expected)
        #expect(throws: Self.notFound(text, as: .task)) {
            try Self.resolve(text, as: .task)
        }
    }

    @Test(
        "A URI of a different node type, a URI that does not parse, or a URI to a missing node gives NOT_FOUND",
        arguments: [
            "\(NodeURI.scheme)\(DependencyMarkersTests.boardKey)/column/doing",
            "\(NodeURI.scheme)\(DependencyMarkersTests.boardKey)/task/not-a-ulid",
            "\(NodeURI.scheme)task/\(ReadinessFixture.first)",
            DependencyMarkersTests.url(ofTask: ReadinessFixture.ghost),
        ]
    )
    func badURIGivesNotFound(reference: String) {
        #expect(throws: Self.notFound(reference, as: .task)) {
            try Self.resolve(reference, as: .task, acceptingRemote: true)
        }
    }

    @Test(
        "The board resolves from the current key and from its URI",
        arguments: [
            DependencyMarkersTests.boardKey,
            "\(NodeURI.scheme)\(DependencyMarkersTests.boardKey)/board",
        ]
    )
    func boardResolves(reference: String) throws {
        #expect(try Self.resolve(reference, as: .board) == .local(.board))
    }

    @Test("A board ref that is not the current key gives NOT_FOUND")
    func otherBoardKeyGivesNotFound() {
        let key = DependencyMarkersTests.otherBoardKey
        #expect(throws: Self.notFound(key, as: .board)) {
            try Self.resolve(key, as: .board)
        }
    }
}
