import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the auto color of a tag (plan.md §6). The cases are a port of the `auto_color` tests of the Rust file
/// `swissarmyhammer-kanban/src/auto_color.rs`. The pinned colors come from the FNV-1a definition alone, not from
/// the Swift code, so the table fails when the Swift result stops to agree with the Rust result.
@Suite("Auto color")
struct AutoColorTests {
    /// The number of colors in the Rust palette.
    static let paletteSize = 16

    /// The number of characters of a color: a 6-character hex value without `#`.
    static let colorLength = 6

    /// The number of tags `tag-0` to `tag-99` of the Rust coverage test.
    static let coverageTagCount = 100

    /// The minimum number of different colors that the coverage tags must get: one half of the palette.
    static let minimumCoverage = 8

    /// The published FNV-1a 32-bit test vectors: each text, with its hash.
    static let hashVectors: [(String, UInt32)] = [
        ("", 0x811c_9dc5),
        ("a", 0xe40c_292c),
        ("foobar", 0xbf9c_f968),
    ]

    /// Each slug of the Rust tests, with the color that the Rust `auto_color` gives for it.
    static let pinnedColors: [(String, String)] = [
        ("bug", "1d76db"),
        ("feature", "bfd4f2"),
        ("docs", "f9c513"),
        ("urgent", "d73a4a"),
        ("low-priority", "e4e669"),
        ("v2", "e36209"),
        ("tag-0", "c5def5"),
        ("tag-1", "e36209"),
    ]

    @Test("The hash is FNV-1a 32-bit", arguments: hashVectors)
    func hashIsFNV1a(text: String, expected: UInt32) {
        #expect(AutoColor.fnv1aHash(of: text) == expected)
    }

    @Test("The auto color equals the Rust result", arguments: pinnedColors)
    func colorEqualsRustResult(slugText: String, expected: String) throws {
        #expect(try Slug(columnOrActorName: slugText).autoColor == expected)
    }

    @Test("Two names with the same slug give the same color")
    func sameSlugGivesSameColor() throws {
        let upper = try Slug(columnOrActorName: "Bug")
        let lower = try Slug(columnOrActorName: "bug")
        #expect(upper.autoColor == lower.autoColor)
    }

    @Test("The palette has 16 different 6-character hex colors")
    func paletteHasSixteenHexColors() {
        #expect(AutoColor.palette.count == Self.paletteSize)
        #expect(Set(AutoColor.palette).count == Self.paletteSize)
        for color in AutoColor.palette {
            #expect(color.count == Self.colorLength)
            #expect(color.allSatisfy { $0.isHexDigit })
        }
    }

    @Test("Each color comes from the palette")
    func colorComesFromPalette() throws {
        for (slugText, _) in Self.pinnedColors {
            #expect(AutoColor.palette.contains(try Slug(columnOrActorName: slugText).autoColor))
        }
    }

    @Test("Many tags get at least half of the palette")
    func manyTagsCoverHalfOfPalette() throws {
        let colors = try (0..<Self.coverageTagCount).map { try Slug(columnOrActorName: "tag-\($0)").autoColor }
        #expect(Set(colors).count >= Self.minimumCoverage)
    }
}
