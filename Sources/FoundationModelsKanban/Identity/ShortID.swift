import Foundation
import ULID

/// The short id of a ULID: the last 7 characters of the ULID, in lowercase (plan.md §3.2).
///
/// The short id is not stored. It is always calculated from the ULID. A person reads it, and an `ID` argument
/// accepts it, with or without a leading `^`.
///
/// The short id is the end of the ULID, not the start. The first 10 characters of a ULID hold the time in
/// milliseconds. Thus, ULIDs that are made at almost the same time have a long common prefix. The last 16
/// characters are random. The last 7 characters give 35 random bits, so the short ids of a board stay unique to
/// approximately 100,000 tasks. The mint rule (``ULIDSource/makeULID(avoiding:)``) makes them unique in each board.
///
/// This is a port of `short_id` in the Rust file `swissarmyhammer-kanban/src/types/short_id.rs`.
struct ShortID: Hashable, Sendable, CustomStringConvertible {
    /// The number of characters at the end of a ULID that make the short id.
    static let length = 7

    /// The number of characters of a full ULID.
    static let ulidLength = 26

    /// The character that can come before a short id in a reference, as in `^ajv8v4t`.
    static let sigil: Character = "^"

    /// The short id: at most ``length`` characters, in lowercase.
    let value: String

    /// The short id as text.
    var description: String {
        value
    }

    /// Calculates the short id of the text of a ULID.
    ///
    /// A text shorter than ``length`` characters gives all of its characters, in lowercase. The calculation has no
    /// error: a text that is not a ULID is an error for the caller to find.
    ///
    /// - Parameter text: The text of a ULID.
    init(ofULIDString text: String) {
        value = text.suffix(Self.length).lowercased()
    }

    /// Calculates the short id of a ULID.
    ///
    /// - Parameter ulid: The ULID.
    init(of ulid: ULID) {
        self.init(ofULIDString: ulid.ulidString)
    }
}

// MARK: - Resolve

extension ShortID {
    /// The result of a resolve of a forgiving ULID reference against a list of ULIDs.
    ///
    /// The result is not an optional, because a reference with more than one match must give the matches. For a
    /// shared short id, the caller picks the first match and gives a warning. For an ambiguous prefix, the caller
    /// shows the matches in its error (`AMBIGUOUS_ID`, plan.md §4.4, divergence.md Q20 and P5).
    enum Resolution: Hashable, Sendable {
        /// Exactly one ULID matched. The value is the ULID text as the list gave it.
        case found(String)

        /// No ULID matched.
        case notFound

        /// More than one ULID has the canonical form of the reference: the short id that a merge gave to two ULIDs
        /// (``collisions(among:)``). The value holds each matching ULID, in list order. The caller picks the first
        /// match by its own order (divergence.md Q20).
        case shared([String])

        /// More than one ULID starts with the prefix. The value holds each matching ULID, in list order.
        case ambiguous([String])
    }

    /// Gives the text that a resolve compares: the reference without white space at the two ends, without one
    /// leading ``sigil``, and in lowercase.
    ///
    /// - Parameter reference: The reference as the caller wrote it, for example `^AJV8V4T`.
    /// - Returns: The search key, for example `ajv8v4t`. A reference of only a sigil gives the empty text.
    static func searchKey(for reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSigil = trimmed.first == sigil ? trimmed.dropFirst() : Substring(trimmed)
        return withoutSigil.lowercased()
    }

    /// Resolves a forgiving ULID reference against a list of ULIDs.
    ///
    /// The reference can be a full ULID, a short id, either of these with a leading ``sigil``, or a ULID prefix (git
    /// style). The compare ignores case. The forms are tried in this order, so a canonical form always wins over a
    /// prefix of the same characters:
    ///
    /// 1. A full ULID that equals the reference.
    /// 2. The ULIDs whose short id equals the reference.
    /// 3. The ULIDs that start with the reference.
    ///
    /// The first form with a match gives the result: one match is ``Resolution/found(_:)``. More than one match of a
    /// canonical form is ``Resolution/shared(_:)``: a short id that two ULIDs share (a merge can make such ULIDs, see
    /// ``collisions(among:)``), and the caller picks the first match. More than one match of a prefix is
    /// ``Resolution/ambiguous(_:)``. When no form has a match, the result is ``Resolution/notFound``.
    ///
    /// An empty reference (after the sigil is removed) is ``Resolution/notFound``. It is not a prefix of each ULID.
    ///
    /// This is a port of `resolve_short_ref` in the Rust file `short_id.rs`.
    ///
    /// - Parameters:
    ///   - reference: The reference as the caller wrote it.
    ///   - ulids: The text of each ULID that the reference can name.
    /// - Returns: The ULID that the reference names, no ULID, each ULID that a shared short id names, or each ULID
    ///   that an ambiguous prefix matches.
    static func resolve(_ reference: String, among ulids: [String]) -> Resolution {
        let key = searchKey(for: reference)
        guard !key.isEmpty else {
            return .notFound
        }
        let canonicalMatches = canonicalMatches(for: key, among: ulids)
        guard canonicalMatches.isEmpty else {
            return resolution(of: canonicalMatches, whenMany: Resolution.shared)
        }
        return resolution(of: ulids.filter { $0.lowercased().hasPrefix(key) }, whenMany: Resolution.ambiguous)
    }

    /// Finds each ULID that a search key names in a canonical form: the full ULID, or the short id.
    ///
    /// - Parameters:
    ///   - key: The search key (see ``searchKey(for:)``).
    ///   - ulids: The text of each ULID that the key can name.
    /// - Returns: Each ULID whose full text or short id equals the key, in list order. The list is empty when the
    ///   key is not as long as a ULID or a short id.
    private static func canonicalMatches(for key: String, among ulids: [String]) -> [String] {
        switch key.count {
        case ulidLength:
            ulids.filter { $0.lowercased() == key }
        case length:
            ulids.filter { ShortID(ofULIDString: $0).value == key }
        default:
            []
        }
    }

    /// Gives the result of a resolve from the ULIDs that one form of the reference matches.
    ///
    /// - Parameters:
    ///   - matches: The matching ULIDs, in list order.
    ///   - makeMany: Makes the result of more than one match of the form: ``Resolution/shared(_:)`` for a canonical
    ///     form, and ``Resolution/ambiguous(_:)`` for a prefix.
    /// - Returns: ``Resolution/notFound`` for no match, ``Resolution/found(_:)`` for one match, and the result of
    ///   `makeMany` for more than one match.
    private static func resolution(of matches: [String], whenMany makeMany: ([String]) -> Resolution) -> Resolution {
        guard let firstMatch = matches.first else {
            return .notFound
        }
        return matches.count == 1 ? .found(firstMatch) : makeMany(matches)
    }
}

// MARK: - Collisions

extension ShortID {
    /// Finds each short id that two or more ULIDs share.
    ///
    /// A short id of only one ULID is not in the result. Thus, an empty result means that the short ids are unique.
    /// The mint rule (``ULIDSource/makeULID(avoiding:)``) keeps the short ids of a board unique. This check finds the
    /// ULIDs that a merge or an old tool made before the rule.
    ///
    /// This is a port of `find_short_id_collisions` in the Rust file `short_id.rs`.
    ///
    /// - Parameter ulids: The text of each ULID to check.
    /// - Returns: Each shared short id, with the ULIDs that give it, in list order.
    static func collisions(among ulids: [String]) -> [ShortID: [String]] {
        Dictionary(grouping: ulids) { ShortID(ofULIDString: $0) }
            .filter { $0.value.count > 1 }
    }
}

// MARK: - Mint rule

extension ULIDSource {
    /// Makes a ULID whose short id is not in a set of short ids (the mint rule of plan.md §3.2).
    ///
    /// The source makes ULIDs until the short id of a ULID is not in `existing`. A collision of short ids is very
    /// rare (35 random bits), so in production the first ULID is almost always the result.
    ///
    /// This is a port of `mint_unique_short_id` in the Rust file `short_id.rs`.
    ///
    /// - Parameter existing: The short ids that are already in the board.
    /// - Returns: The first ULID of the source whose short id is not in `existing`.
    mutating func makeULID(avoiding existing: Set<ShortID>) -> ULID {
        var candidate = makeULID()
        while existing.contains(ShortID(of: candidate)) {
            candidate = makeULID()
        }
        return candidate
    }
}
