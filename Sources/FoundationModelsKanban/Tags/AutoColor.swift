import Foundation

/// The automatic color of a tag: a fixed color for each slug (plan.md §6).
///
/// The color is the FNV-1a 32-bit hash of the slug, modulo the number of colors in ``palette``. The hash and the
/// palette are the same as in Rust, so a tag gets the same color in the two tools. Do not change the hash or the
/// palette: a change gives new colors to the tags that exist.
///
/// This is a port of `auto_color` in the Rust file `swissarmyhammer-kanban/src/auto_color.rs`.
enum AutoColor {
    /// The 16 tag colors: 6-character hex values without `#`. The order is the order of the Rust palette.
    static let palette = [
        "d73a4a",  // red
        "e36209",  // orange
        "f9c513",  // yellow
        "0e8a16",  // green
        "006b75",  // teal
        "1d76db",  // blue
        "5319e7",  // purple
        "b60205",  // dark red
        "d876e3",  // pink
        "0075ca",  // ocean
        "7057ff",  // violet
        "008672",  // sea green
        "e4e669",  // lime
        "bfd4f2",  // light blue
        "c5def5",  // periwinkle
        "fbca04",  // gold
    ]

    /// The FNV-1a 32-bit offset basis: the hash of the empty text. It is part of the published algorithm.
    static let fnvOffsetBasis: UInt32 = 0x811c_9dc5

    /// The FNV-1a 32-bit prime: the multiplier for each byte. It is part of the published algorithm.
    static let fnvPrime: UInt32 = 0x0100_0193

    /// Calculates the FNV-1a 32-bit hash of the UTF-8 bytes of a text.
    ///
    /// For each byte, the hash is XOR the byte, and then multiplied by ``fnvPrime`` with overflow.
    ///
    /// - Parameter text: The text to hash.
    /// - Returns: The hash.
    static func fnv1aHash(of text: String) -> UInt32 {
        text.utf8.reduce(fnvOffsetBasis) { hash, byte in
            (hash ^ UInt32(byte)) &* fnvPrime
        }
    }

    /// Gives the color of a text from ``palette``.
    ///
    /// - Parameter text: The text, for example a slug.
    /// - Returns: The color at the index hash modulo the palette size.
    static func color(forText text: String) -> String {
        palette[Int(fnv1aHash(of: text) % UInt32(palette.count))]
    }
}

extension Slug {
    /// The automatic color of the tag with this slug, for example `1d76db` for `bug`.
    var autoColor: String {
        AutoColor.color(forText: value)
    }
}

extension TagNode {
    /// The color that the tag shows: the color that a patch set, else the auto color of the slug (plan.md §6).
    var resolvedColor: String {
        color ?? AutoColor.color(forText: slug)
    }
}
