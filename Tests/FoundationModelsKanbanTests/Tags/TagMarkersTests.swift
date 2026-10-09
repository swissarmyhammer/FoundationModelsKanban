import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the `#tag` markers of a task body: the parse and the remove (plan.md §6.1). The cases are a port of the
/// tests in the Rust file `swissarmyhammer-kanban/src/tag_parser.rs`. The Swift parse gives each marker as its slug,
/// so the expected tags are in lowercase.
@Suite("Tag markers")
struct TagMarkersTests {
    /// A tag name with a space, as the caller writes it.
    static let spacedTagName = "needs review"

    /// The tag name that the tag name rule gives for ``spacedTagName``: the space becomes `_` (plan.md §6).
    static let underscoreMarker = "needs_review"

    /// The slug of ``underscoreMarker``.
    static let underscoreMarkerSlug = "needs-review"

    /// The text of ``underscoreMarker`` before its `_`. A marker of ``underscoreMarker`` must not give this slug.
    static let underscoreMarkerHead = "needs"

    /// Each body with a marker that has `_`, with the slugs that the parse gives, in text order.
    static let underscoreParseCases: [(String, [String])] = [
        ("Fix #\(underscoreMarker) now", [underscoreMarkerSlug]),
        ("#Needs_Review", [underscoreMarkerSlug]),
        ("#needs__review_ and #\(underscoreMarkerHead)", [underscoreMarkerSlug, underscoreMarkerHead]),
        ("#_needs", []),
        ("#a_#b", ["a"]),
    ]

    /// Each remove of a tag from a body with a marker that has `_`: the tag name, the body, and the body after the
    /// remove.
    static let underscoreRemoveCases: [(String, String, String)] = [
        (spacedTagName, "fix #\(underscoreMarker) now", "fix now"),
        (underscoreMarkerHead, "fix #\(underscoreMarker) now", "fix #\(underscoreMarker) now"),
    ]

    /// Each body of the Rust parse tests, with the slugs that the parse gives, in text order.
    static let parseCases: [(String, [String])] = [
        ("Fix the #bug in #login", ["bug", "login"]),
        ("#bug and #bug again", ["bug"]),
        ("text #real\n```\n#fake\n```\nmore #also-real", ["real", "also-real"]),
        ("use `#not-a-tag` but #real", ["real"]),
        ("# Heading\n## Sub heading\n#real-tag here", ["real-tag"]),
        ("this is #high-priority stuff", ["high-priority"]),
        ("#bug at the start", ["bug"]),
        ("at the end #bug", ["bug"]),
        ("no tags here", []),
        ("", []),
        ("#Bug #sample! #CamelCase #emoji🎉", ["bug", "sample", "camelcase", "emoji"]),
        ("#[serial(cwd)]", []),
        ("#(foo)", []),
        ("#!x", []),
        ("#-x", []),
        ("#bug,", ["bug"]),
        ("#bug.", ["bug"]),
        ("#bug", ["bug"]),
        ("#multi-word-tag", ["multi-word-tag"]),
    ]

    /// Each body of the Rust remove tests, with the body after the remove of `#bug`.
    static let removeCases: [(String, String)] = [
        ("fix #bug in code", "fix in code"),
        ("fix issue #bug", "fix issue"),
        ("no tags here", "no tags here"),
        ("text #bug\n```\n#bug inside\n```", "text\n```\n#bug inside\n```"),
        ("text — with #bug em dash", "text — with em dash"),
        ("prose\n#bug\nmore", "prose\n\nmore"),
        ("prose\n#bug\n", "prose\n\n"),
        ("prose\n#bug", "prose"),
        ("a\n\n#bug", "a\n"),
        ("a\n\n\n#bug", "a\n\n"),
        ("keep me   \nfix #bug  \nkeep me too   \n", "keep me   \nfix\nkeep me too   \n"),
        ("fix #bug, then ship", "fix, then ship"),
        ("done #bug.", "done."),
        ("a #bug! b", "a! b"),
        ("see (#bug) here", "see () here"),
        ("# Fix #bug\n\nsee also #bug", "# Fix #bug\n\nsee also"),
    ]

    /// Each tagged body that the Rust append writes, with the body before the append. The remove gives that body
    /// back: the marker on its own last line goes away together with the line break before it.
    static let appendedCases: [(String, String)] = [
        ("Repro:\n```\ncargo test\n```\n#bug", "Repro:\n```\ncargo test\n```"),
        ("Intro\n\n## Acceptance\n#bug", "Intro\n\n## Acceptance"),
        ("# Just a heading\n#bug", "# Just a heading"),
        ("plain body #bug", "plain body"),
        ("#bug", ""),
        ("prose\n\n#bug", "prose\n"),
        ("body   \n#bug", "body   "),
    ]

    /// Bodies with no marker of `bug`. The remove must give each one back, byte for byte.
    static let bystanderBodies = [
        "No marker here   \nsecond line",
        "trailing newline survives\n",
        "  indented and padded   ",
        "# Heading   \n\nbody   ",
        "```\n#bug inside   \n```\n",
        "windows\r\nline endings\r\n",
        "blank line then space\n   \n",
        "",
        "fix #other   \nsecond   \n",
        "#other   \n",
        "#other and #another   ",
        "### Notes on offender #bug (perspective-tab-bar)\n\nNot a violation today.\n",
        "## RESOLVED \u{2014} absorbed by card #bug (commit fb522e8a2)\n\nNothing left to do.\n",
    ]

    /// One fragment for each line shape that the line walk classifies. A body of each ordered triple of these makes
    /// each shape meet each other shape, above it and below it.
    static let lineShapes = [
        "#bug", "a #bug b", "#bug,", "#bug #bug", "  #bug", "    #bug", "# bug", "# Fix #bug", "## #bug",
        "### Notes on offender #bug (x)", "###bug", "```", "~~~", "`#bug`", "x`#bug", "#bug`x`", "a#bug", "#!bug",
        "#-bug", "text", "",
    ]

    /// The line breaks that the line walk keeps.
    static let lineBreaks = ["\n", "\r\n"]

    /// Gives the slug of a tag name.
    ///
    /// - Parameter name: The tag name.
    /// - Returns: The slug.
    /// - Throws: An error when the name gives an empty slug.
    static func slug(of name: String) throws -> Slug {
        try TagName(normalizing: name).slug
    }

    /// Gives the text of the slugs that the parse finds in a body.
    ///
    /// - Parameter body: The body.
    /// - Returns: The slug texts, in text order.
    static func slugTexts(in body: String) -> [String] {
        TagMarkers.slugs(in: body).map(\.value)
    }

    /// Gives the content of each line of a body that the parse skips, with the position of the line.
    ///
    /// - Parameter body: The body.
    /// - Returns: The position and the content of each skipped line.
    static func skippedLines(of body: String) -> [(position: Int, content: Substring)] {
        let lines = BodyLines.lines(of: body)
        return zip(lines.indices, TagMarkers.tagBearingFlags(of: lines))
            .filter { _, isTagBearing in !isTagBearing }
            .map { position, _ in (position, BodyLines.content(of: lines[position])) }
    }

    // MARK: - Parse

    @Test("The parse gives the slug of each marker one time, in text order", arguments: parseCases)
    func parseGivesSlugs(body: String, expected: [String]) {
        #expect(Self.slugTexts(in: body) == expected)
    }

    @Test("Two markers that differ only in case give one tag")
    func parseIgnoresCase() {
        #expect(Self.slugTexts(in: "#Bug and #bug and #BUG") == ["bug"])
    }

    @Test("A marker glued to the end of a word is not a tag")
    func gluedMarkerIsNotTag() {
        #expect(Self.slugTexts(in: "a#bug b_#bug c9#bug").isEmpty)
    }

    @Test("A trailing hyphen is not part of the slug")
    func trailingHyphenIsNotPartOfSlug() {
        #expect(Self.slugTexts(in: "see #bug- now") == ["bug"])
    }

    @Test("A marker keeps each _ in its text and gives the slug of the full name", arguments: underscoreParseCases)
    func parseKeepsUnderscore(body: String, expected: [String]) {
        #expect(Self.slugTexts(in: body) == expected)
    }

    @Test("A marker in a fence that opens with tildes is not a tag")
    func tildeFenceHidesMarker() {
        #expect(Self.slugTexts(in: "~~~\n#fake\n~~~\n#real") == ["real"])
    }

    // MARK: - Remove

    @Test("A remove takes each marker of the tag out of the body", arguments: removeCases)
    func removeTakesOutMarkers(body: String, expected: String) throws {
        let result = TagMarkers.removing(markersOf: try Self.slug(of: "bug"), from: body)
        #expect(result == expected)
        #expect(!Self.slugTexts(in: result).contains("bug"))
    }

    @Test("A remove of the marker that the append wrote gives the body back", arguments: appendedCases)
    func removeUndoesAppend(tagged: String, original: String) throws {
        #expect(TagMarkers.removing(markersOf: try Self.slug(of: "bug"), from: tagged) == original)
    }

    @Test("A remove takes out a full marker with _, and only for its slug", arguments: underscoreRemoveCases)
    func removeKeepsUnderscore(name: String, body: String, expected: String) throws {
        #expect(TagMarkers.removing(markersOf: try Self.slug(of: name), from: body) == expected)
    }

    @Test("A remove gives a body with no marker of the tag back, byte for byte", arguments: bystanderBodies)
    func removeKeepsBystanderBody(body: String) throws {
        #expect(TagMarkers.removing(markersOf: try Self.slug(of: "bug"), from: body) == body)
    }

    @Test("A remove takes out a marker that differs from the slug only in case")
    func removeIgnoresCase() throws {
        let result = TagMarkers.removing(markersOf: try Self.slug(of: "bug"), from: "fix #Bug and #BUG now")
        #expect(result == "fix and now")
    }

    @Test("A remove keeps each line that the parse skips, at its position", arguments: lineBreaks)
    func removeKeepsSkippedLines(lineBreak: String) throws {
        let slug = try Self.slug(of: "bug")
        for above in Self.lineShapes {
            for middle in Self.lineShapes {
                for below in Self.lineShapes {
                    let body = [above, middle, below].joined(separator: lineBreak)
                    let written = TagMarkers.removing(markersOf: slug, from: body)
                    let after = BodyLines.lines(of: written).map(BodyLines.content(of:))
                    for line in Self.skippedLines(of: body) {
                        #expect(after.dropFirst(line.position).first == line.content, "\(body.debugDescription)")
                    }
                }
            }
        }
    }
}
