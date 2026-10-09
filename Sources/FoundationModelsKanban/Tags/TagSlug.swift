import Foundation

/// The slug of a tag, a column, or an actor: the identifier of the node (plan.md §3.2).
///
/// A slug has only lowercase ASCII letters, ASCII digits, and `-`. It does not start or end with `-`, and it is not
/// empty. Two names that differ only in case give the same slug, so `Bug` and `bug` are one node, and one file on a
/// disk that ignores case.
///
/// The initializers of this type check the rule. Thus, each `Slug` value obeys it.
struct Slug: Hashable, Sendable, CustomStringConvertible {
    /// The character that replaces each run of characters that a slug does not keep.
    static let separator: Character = "-"

    /// The slug that no column, actor, or tag can have: `board`, the last segment of the board URI
    /// `kanban://<board-key>/board` (plan.md §3.2). The parse reads each URI whose last segment is `board` as the
    /// board URI, so the URI `kanban://<board-key>/column/board` is the board of the key `<board-key>/column`.
    static let reservedForBoard = PatchNodeType.board.pathSegment

    /// The slug text, for example `bug-fix`.
    let value: String

    /// The slug as text.
    var description: String {
        value
    }

    /// Makes the slug of a name, when the slug is not empty.
    ///
    /// - Parameter name: The name, for example `Bug Fix`.
    fileprivate init?(nonEmptySlugOf name: String) {
        let text = Self.normalizedText(of: name)
        guard !text.isEmpty else {
            return nil
        }
        value = text
    }

    /// Makes the slug of the name of a column or an actor.
    ///
    /// - Parameter name: The name as the caller wrote it, for example `Claude Code`.
    /// - Throws: ``KanbanError/invalidSlug(name:)`` when the name gives an empty slug.
    init(columnOrActorName name: String) throws(KanbanError) {
        guard let slug = Slug(nonEmptySlugOf: name) else {
            throw .invalidSlug(name: name)
        }
        self = slug
    }

    /// Gives the slug text of a name.
    ///
    /// Each ASCII letter and ASCII digit stays, in lowercase. Each run of other Unicode scalars (spaces,
    /// punctuation, `_`, `#`, NUL, and all scalars that are not ASCII) becomes one ``separator``. The text does not
    /// start or end with a ``separator``. A name with no ASCII letter or digit gives the empty text.
    ///
    /// This is a port of `normalize_slug` in the Rust file `swissarmyhammer-kanban/src/tag_parser.rs`. The Rust
    /// function keeps case. This function changes the text to lowercase (plan.md §3.2). The function examines each
    /// Unicode scalar, as the Rust function examines each `char`. Thus, `e` followed by a combining accent keeps
    /// the `e`. The lowercase change comes after the ASCII check, so the Kelvin sign (U+212A) does not become `k`.
    ///
    /// - Parameter name: The name, for example `Bug Fix`.
    /// - Returns: The slug text, for example `bug-fix`, or the empty text.
    static func normalizedText(of name: String) -> String {
        var text = ""
        // A separator before the first kept scalar is not written, so the start counts as a separator.
        var lastWasSeparator = true
        for scalar in name.unicodeScalars {
            if scalar.isASCIIAlphanumeric {
                text.append(Character(scalar).lowercased())
                lastWasSeparator = false
            } else if !lastWasSeparator {
                text.append(separator)
                lastWasSeparator = true
            }
        }
        if text.last == separator {
            text.removeLast()
        }
        return text
    }
}

extension LocalRef {
    /// Checks that a mutation can make a node with this ref: a column, an actor, or a tag must not have the slug
    /// ``Slug/reservedForBoard`` (plan.md §3.2), and a tag must not have the name of a virtual tag as its slug
    /// (plan.md §6). A slug is in lowercase, so the check ignores the case of the name that gave the slug. Replay does
    /// not use this check, so a log that already has such a node still loads.
    ///
    /// - Throws: ``KanbanError/virtualTagName(tag:)`` for a tag whose slug is the name of a virtual tag.
    ///   ``KanbanError/reservedTagName`` for a tag, and ``KanbanError/reservedSlug(type:)`` for a column or an actor,
    ///   when the slug is ``Slug/reservedForBoard``.
    func checkSlugIsNotReserved() throws(KanbanError) {
        if nodeType == .tag, let virtualTag = localID.flatMap(VirtualTag.init(named:)) {
            throw .virtualTagName(tag: virtualTag)
        }
        guard localID == Slug.reservedForBoard else {
            return
        }
        throw nodeType == .tag ? .reservedTagName : .reservedSlug(type: nodeType)
    }
}

extension Unicode.Scalar {
    /// `true` when the scalar is an ASCII letter or an ASCII digit: a scalar that a slug keeps. This is the same
    /// test as `char::is_ascii_alphanumeric` in Rust.
    var isASCIIAlphanumeric: Bool {
        isASCII && (properties.isAlphabetic || properties.numericType != nil)
    }
}

/// The name of a tag, and its slug (plan.md §6).
///
/// The name keeps the case of the caller. The slug is the identifier of the tag.
struct TagName: Hashable, Sendable {
    /// The character that replaces each run of white space in a tag name.
    static let spaceReplacement: Character = "_"

    /// The NUL scalar, which a tag name does not keep.
    static let nul: Unicode.Scalar = "\u{0}"

    /// The tag name, for example `Bug_Fix`.
    let name: String

    /// The slug of the tag name, for example `bug-fix`.
    let slug: Slug

    /// Makes a tag name with the tag name rule.
    ///
    /// The rule removes each NUL, removes the white space at the two ends, and changes each run of white space to
    /// one ``spaceReplacement``. The slug is the slug of the result. NUL is removed first, so that a NUL between two
    /// spaces does not stop one run of spaces.
    ///
    /// - Parameter raw: The tag name as the caller wrote it, for example `  Bug  Fix `.
    /// - Throws: ``KanbanError/invalidTagName(name:)`` when the name gives an empty slug. An empty name also gives
    ///   an empty slug.
    init(normalizing raw: String) throws(KanbanError) {
        let name = Self.cleanedName(from: raw)
        guard let slug = Slug(nonEmptySlugOf: name) else {
            throw .invalidTagName(name: raw)
        }
        self.name = name
        self.slug = slug
    }

    /// Applies the tag name rule to a name: no NUL, no white space at the two ends, and one ``spaceReplacement`` for
    /// each run of white space.
    ///
    /// - Parameter raw: The tag name as the caller wrote it.
    /// - Returns: The tag name.
    private static func cleanedName(from raw: String) -> String {
        String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0 != nul }))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: String(spaceReplacement))
    }
}
