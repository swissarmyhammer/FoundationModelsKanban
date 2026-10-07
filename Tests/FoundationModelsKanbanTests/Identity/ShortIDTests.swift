import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the short id of a ULID, the resolve of a short reference, the collision check, the mint rule, and the
/// ULID sources (plan.md §3.2). The cases are a port of the cases of the Rust file
/// `swissarmyhammer-kanban/src/types/short_id.rs`.
@Suite("Short ids")
struct ShortIDTests {
    // Real ULIDs from the short-ids epic board of the Rust project. The four `01KT6SA…` siblings have the same
    // 7-character prefix `01KT6SA`. The resolve must report this prefix as ambiguous.

    /// A ULID whose short id is `ajv8v4t`.
    static let core = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The first sibling. It is the only id that starts with `01KT6SAM`.
    static let siblingA = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The second sibling.
    static let siblingB = "01KT6SA4911JQPK09YQRC9RB4G"

    /// The third sibling.
    static let siblingC = "01KT6SAAM6CR85YZD26JHSC87E"

    /// The fourth sibling.
    static let siblingD = "01KT6SAXCBZFE6S0DEPZDJSQAA"

    /// The four siblings.
    static let siblings = [siblingA, siblingB, siblingC, siblingD]

    /// The ids of the test board: ``core`` and the four siblings.
    static let board = [core] + siblings

    /// A ULID whose short id is `0123456`.
    static let ownerOf0123456 = "01KT6R6HR3KJT6JVNDR0123456"

    /// A different ULID whose short id is also `0123456`.
    static let secondOwnerOf0123456 = "01KT6SAMJAJ40XVQ9YJ0123456"

    /// A ULID whose short id is `abcdefg`.
    static let ownerOfABCDEFG = "01KT6SAMJAJ40XVQ9YJABCDEFG"

    /// The fixed clock of the test ULID source: 2027-01-15 08:00:00 UTC.
    static let fixedTimestamp = Date(timeIntervalSince1970: 1_800_000_000)

    /// The number of ULIDs that a determinism test takes from a test source.
    static let sequenceLength = 20

    // MARK: - Short id

    @Test("The short id is the last 7 characters of the ULID, in lowercase")
    func shortIDIsLastSevenLowercased() {
        let shortID = ShortID(ofULIDString: Self.core)
        #expect(shortID.value == "ajv8v4t")
        #expect(shortID.value.count == ShortID.length)
    }

    @Test("The short id of a ULID value equals the short id of its text")
    func shortIDOfULIDMatchesShortIDOfText() throws {
        let ulid = try #require(ULID(ulidString: Self.core))
        #expect(ShortID(of: ulid) == ShortID(ofULIDString: Self.core))
    }

    @Test("The ULID ends with its short id when both are in lowercase")
    func shortIDIsTheLowercasedSuffix() {
        let shortID = ShortID(ofULIDString: Self.siblingA)
        #expect(Self.siblingA.lowercased().hasSuffix(shortID.value))
    }

    @Test("A text shorter than 7 characters gives all of its characters, in lowercase")
    func shortTextGivesAllCharacters() {
        #expect(ShortID(ofULIDString: "AbC").value == "abc")
    }

    @Test("The description of a short id is its value")
    func descriptionIsValue() {
        #expect(ShortID(ofULIDString: Self.core).description == "ajv8v4t")
    }

    // MARK: - Search key

    @Test("The search key removes the white space and one caret, and is in lowercase")
    func searchKeyRemovesCaretAndSpace() {
        #expect(ShortID.searchKey(for: "  ^AJV8V4T \n") == "ajv8v4t")
        #expect(ShortID.searchKey(for: "^^ajv8v4t") == "^ajv8v4t")
        #expect(ShortID.searchKey(for: "^") == "")
    }

    // MARK: - Resolve

    @Test("A full ULID resolves to its id")
    func resolvesFullULID() {
        #expect(ShortID.resolve(Self.core, among: Self.board) == .found(Self.core))
    }

    @Test("An exact short id resolves to its id")
    func resolvesExactShortID() {
        #expect(ShortID.resolve("ajv8v4t", among: Self.board) == .found(Self.core))
    }

    @Test("A short id with a caret resolves to its id")
    func resolvesCaretPrefixedShortID() {
        #expect(ShortID.resolve("^ajv8v4t", among: Self.board) == .found(Self.core))
    }

    @Test("The resolve ignores case")
    func resolutionIsCaseInsensitive() {
        #expect(ShortID.resolve("AJV8V4T", among: Self.board) == .found(Self.core))
        #expect(ShortID.resolve(Self.core.lowercased(), among: Self.board) == .found(Self.core))
    }

    @Test("A unique ULID prefix resolves to its id")
    func resolvesUniqueULIDPrefix() {
        #expect(ShortID.resolve("01KT6SAM", among: Self.board) == .found(Self.siblingA))
    }

    @Test("An ambiguous prefix gives all of the matching ids")
    func ambiguousPrefixReportsAllMatches() {
        #expect(ShortID.resolve("01KT6SA", among: Self.board) == .ambiguous(Self.siblings))
    }

    @Test("An exact short id wins over a prefix that matches more than one id")
    func exactShortIDBeatsCollidingPrefix() {
        let prefixA = "0123456AAAAAAAAAAAAAAAAAAAA"
        let prefixB = "0123456BBBBBBBBBBBBBBBBBBBB"
        let ids = [Self.ownerOf0123456, prefixA, prefixB]
        #expect(ShortID(ofULIDString: Self.ownerOf0123456).value == "0123456")
        #expect(ShortID.resolve("0123456", among: ids) == .found(Self.ownerOf0123456))
    }

    @Test("An unknown reference is not found")
    func unknownReferenceIsNotFound() {
        #expect(ShortID.resolve("zzzzzzz", among: Self.board) == .notFound)
        #expect(ShortID.resolve("^zzzzzzz", among: Self.board) == .notFound)
    }

    @Test("An empty reference is not found")
    func emptyReferenceIsNotFound() {
        #expect(ShortID.resolve("", among: Self.board) == .notFound)
        #expect(ShortID.resolve("^", among: Self.board) == .notFound)
    }

    // MARK: - Collisions

    @Test("Ids with different short ids have no collision")
    func noCollisionsOnDistinctShortIDs() {
        #expect(ShortID.collisions(among: Self.board).isEmpty)
    }

    @Test("Two ids with the same short id give one collision")
    func detectsASharedShortID() {
        let ids = [Self.ownerOf0123456, Self.secondOwnerOf0123456, Self.core]
        let collisions = ShortID.collisions(among: ids)
        #expect(collisions == [ShortID(ofULIDString: "0123456"): [Self.ownerOf0123456, Self.secondOwnerOf0123456]])
    }

    @Test("The collision check ignores case")
    func collisionDetectionIsCaseInsensitive() {
        let upper = "01KT6R6HR3KJT6JVNDRABCDEFG"
        let lower = "01KT6SAMJAJ40XVQ9Yjabcdefg"
        #expect(ShortID(ofULIDString: upper) == ShortID(ofULIDString: lower))
        #expect(ShortID.collisions(among: [upper, lower]).count == 1)
    }

    // MARK: - Mint rule

    @Test("The mint rule keeps the first ULID when its short id is unique")
    func mintAcceptsFirstUniqueCandidate() throws {
        let first = try #require(ULID(ulidString: Self.core))
        var source = ScriptedULIDSource(candidates: [first])
        let minted = source.makeULID(avoiding: [])
        #expect(minted == first)
        #expect(source.callCount == 1)
    }

    @Test("The mint rule skips a ULID whose short id is in the set")
    func mintRetriesPastACollidingCandidate() throws {
        let colliding = try #require(ULID(ulidString: Self.ownerOf0123456))
        let unique = try #require(ULID(ulidString: Self.ownerOfABCDEFG))
        var source = ScriptedULIDSource(candidates: [colliding, unique])
        let existing: Set<ShortID> = [ShortID(ofULIDString: "0123456")]
        let minted = source.makeULID(avoiding: existing)
        #expect(minted == unique)
        #expect(ShortID(of: minted).value == "abcdefg")
        #expect(!existing.contains(ShortID(of: minted)))
    }

    @Test("The mint rule never gives a short id of the set")
    func mintNeverReturnsAnExistingShortID() {
        var taken = FixedULIDSource(at: Self.fixedTimestamp)
        let existing = Set((0..<Self.sequenceLength).map { _ in ShortID(of: taken.makeULID()) })
        var source = FixedULIDSource(at: Self.fixedTimestamp)
        let minted = source.makeULID(avoiding: existing)
        #expect(!existing.contains(ShortID(of: minted)))
        #expect(minted == taken.makeULID())
    }

    // MARK: - ULID sources

    @Test("The test ULID source gives the same sequence on each run")
    func fixedSourceIsDeterministic() {
        var first = FixedULIDSource(at: Self.fixedTimestamp)
        var second = FixedULIDSource(at: Self.fixedTimestamp)
        let firstRun = (0..<Self.sequenceLength).map { _ in first.makeULID() }
        let secondRun = (0..<Self.sequenceLength).map { _ in second.makeULID() }
        #expect(firstRun == secondRun)
    }

    @Test("The test ULID source gives ULIDs in sort order, with different short ids, at the fixed time")
    func fixedSourceGivesSortedDistinctULIDs() {
        var source = FixedULIDSource(at: Self.fixedTimestamp)
        let ulids = (0..<Self.sequenceLength).map { _ in source.makeULID() }
        #expect(ulids == ulids.sorted())
        #expect(Set(ulids.map { ShortID(of: $0) }).count == Self.sequenceLength)
        #expect(ulids.allSatisfy { $0.timestamp == Self.fixedTimestamp })
    }

    @Test("The system ULID source gives different ULIDs")
    func systemSourceGivesDifferentULIDs() {
        let source = SystemULIDSource()
        let ulids = Set((0..<Self.sequenceLength).map { _ in source.makeULID() })
        #expect(ulids.count == Self.sequenceLength)
    }
}

/// A ULID source that gives a fixed list of ULIDs, in order, and counts the calls. The mint tests use it to make
/// the first candidate collide.
struct ScriptedULIDSource: ULIDSource {
    /// The ULIDs to give, in order.
    let candidates: [ULID]

    /// The number of ULIDs that the source gave.
    private(set) var callCount = 0

    /// Makes a source that gives the ULIDs of `candidates`, in order.
    ///
    /// - Parameter candidates: The ULIDs to give.
    init(candidates: [ULID]) {
        self.candidates = candidates
    }

    /// Gives the next ULID of the list.
    ///
    /// - Returns: The next ULID of the list.
    mutating func makeULID() -> ULID {
        defer { callCount += 1 }
        return candidates[callCount]
    }
}
