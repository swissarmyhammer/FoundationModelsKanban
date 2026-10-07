import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the slug rule (plan.md §3.2) and the tag name rule (plan.md §6). The slug cases are a port of
/// `test_normalize_slug` in the Rust file `swissarmyhammer-kanban/src/tag_parser.rs`, with the slugs in lowercase.
@Suite("Slugs and tag names")
struct TagSlugTests {
    /// Each raw name of the Rust slug test, with the slug that the Swift rule gives.
    static let slugCases: [(String, String)] = [
        ("Bug Fix", "bug-fix"),
        ("high_priority", "high-priority"),
        ("UPPERCASE", "uppercase"),
        ("--trim--", "trim"),
        ("keep-123", "keep-123"),
        ("#hashtag", "hashtag"),
        ("émojis 🎉", "mojis"),
        ("v2.0", "v2-0"),
        ("Cafe\u{301} au lait", "cafe-au-lait"),
    ]

    /// Names that have no ASCII letter or digit, so they give an empty slug.
    /// The Kelvin sign `K` (U+212A) is not ASCII, but its lowercase form is the ASCII `k`. The Rust rule does not
    /// keep it, so the Swift rule must not keep it.
    static let namesWithoutSlug = ["", "   ", "---", "#!?", "🎉", "\u{0}", "\u{212A}"]

    // MARK: - Slug text

    @Test("The slug text is the Rust slug, in lowercase", arguments: slugCases)
    func slugTextIsLowercaseRustSlug(raw: String, expected: String) {
        #expect(Slug.normalizedText(of: raw) == expected)
    }

    @Test("A name with no letter or digit gives an empty slug text", arguments: namesWithoutSlug)
    func nameWithoutLetterGivesEmptyText(raw: String) {
        #expect(Slug.normalizedText(of: raw).isEmpty)
    }

    @Test("A run of other characters becomes one hyphen")
    func runBecomesOneHyphen() {
        #expect(Slug.normalizedText(of: "a  .. b") == "a-b")
    }

    // MARK: - Column and actor slugs

    @Test("Bug and bug give the same column or actor slug")
    func columnSlugIgnoresCase() throws {
        let upper = try Slug(columnOrActorName: "Bug")
        let lower = try Slug(columnOrActorName: "bug")
        #expect(upper == lower)
        #expect(upper.value == "bug")
    }

    @Test("A column or actor slug follows the slug rule")
    func columnSlugFollowsRule() throws {
        #expect(try Slug(columnOrActorName: "Claude Code").value == "claude-code")
    }

    @Test("A column or actor name with an empty slug gives INVALID_SLUG", arguments: namesWithoutSlug)
    func emptyColumnSlugIsRefused(raw: String) {
        #expect(throws: KanbanError.invalidSlug(name: raw)) {
            try Slug(columnOrActorName: raw)
        }
        #expect(KanbanError.invalidSlug(name: raw).code == "INVALID_SLUG")
    }

    @Test("The description of a slug is its value")
    func descriptionIsValue() throws {
        #expect(try Slug(columnOrActorName: "Doing").description == "doing")
    }

    // MARK: - Tag names

    @Test("Bug and bug give the same tag slug")
    func tagSlugIgnoresCase() throws {
        let upper = try TagName(normalizing: "Bug")
        let lower = try TagName(normalizing: "bug")
        #expect(upper.slug == lower.slug)
        #expect(upper.slug.value == "bug")
    }

    @Test("The tag name keeps its case")
    func tagNameKeepsCase() throws {
        #expect(try TagName(normalizing: "Bug").name == "Bug")
    }

    @Test("The tag name is trimmed, and each run of spaces becomes one underscore")
    func tagNameTrimsAndJoinsSpaces() throws {
        let tag = try TagName(normalizing: "  Bug   Fix \n")
        #expect(tag.name == "Bug_Fix")
        #expect(tag.slug.value == "bug-fix")
    }

    @Test("The tag name has no NUL")
    func tagNameRemovesNul() throws {
        #expect(try TagName(normalizing: "a\u{0}b").name == "ab")
        #expect(try TagName(normalizing: "a \u{0} b").name == "a_b")
    }

    @Test("A tag name with an empty slug gives INVALID_TAG_NAME", arguments: namesWithoutSlug)
    func emptyTagNameIsRefused(raw: String) {
        #expect(throws: KanbanError.invalidTagName(name: raw)) {
            try TagName(normalizing: raw)
        }
        #expect(KanbanError.invalidTagName(name: raw).code == "INVALID_TAG_NAME")
    }
}
