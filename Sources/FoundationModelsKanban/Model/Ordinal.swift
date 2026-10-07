import Foundation

/// The order of a task in its column: a fractional index (plan.md §6).
///
/// An ordinal is a list of bytes, and the last byte is always ``terminator``. The text form, ``value``, is the
/// lowercase hex of all the bytes, for example `80`. Two ordinals sort in the same order as their bytes, and also in
/// the same order as their texts. Between two different ordinals, there is always space for one more ordinal. Thus,
/// a task can always move between two neighbors, and no other task gets a new ordinal.
///
/// This is the algorithm of the Rust crate `fractional_index` 2.0.2 (the Figma algorithm), which the Rust file
/// `swissarmyhammer-kanban/src/types/position.rs` uses. Byte compatibility with Rust data is not necessary, because
/// the storage is new.
///
/// The initializers of this type keep the rule. Thus, each `Ordinal` value is a valid fractional index.
struct Ordinal: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The byte at the end of each ordinal. A byte less than the terminator sorts before the end of a shorter
    /// ordinal, and a byte greater than the terminator sorts after it.
    static let terminator: UInt8 = 0x80

    /// The ordinal of the first task in an empty column. Its bytes are only the ``terminator``.
    static let first = Ordinal(bytes: [terminator])

    /// The text of ``first``: `80`. A missing ordinal sorts as this text.
    static let defaultText = first.value

    /// The ASCII codes of the hex digits, in the order of their values.
    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// The number of hex digits that give one byte.
    private static let hexDigitsPerByte = 2

    /// The number of bits of one hex digit.
    private static let bitsPerHexDigit: UInt8 = 4

    /// The mask that keeps the low hex digit of a byte.
    private static let lowHexDigitMask: UInt8 = 0x0f

    /// The divisor that gives the middle of the gap between two bytes.
    private static let midpointDivisor = 2

    /// The bytes of the ordinal. The last byte is the ``terminator``.
    private let bytes: [UInt8]

    /// The ordinal as text: the lowercase hex of its bytes, for example `7f80`.
    var value: String {
        let digits = bytes.flatMap { byte in
            [Self.hexDigits[Int(byte >> Self.bitsPerHexDigit)], Self.hexDigits[Int(byte & Self.lowHexDigitMask)]]
        }
        return String(decoding: digits, as: UTF8.self)
    }

    /// The ordinal as text, the same as ``value``.
    var description: String {
        value
    }

    /// Makes an ordinal from bytes that end with the ``terminator``.
    ///
    /// - Parameter bytes: The bytes, with the ``terminator`` at the end.
    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Makes an ordinal from bytes that do not have the ``terminator`` yet.
    ///
    /// - Parameter unterminatedBytes: The bytes, without the ``terminator``.
    private init(unterminated unterminatedBytes: [UInt8]) {
        bytes = unterminatedBytes + [Self.terminator]
    }

    /// Reads an ordinal from its text.
    ///
    /// The text must be lowercase hex with an even number of digits, and the last byte must be the ``terminator``.
    ///
    /// - Parameter text: The ordinal text, for example `8180`.
    /// - Throws: ``KanbanError/invalidOrdinal(ordinal:)`` when the text is not a valid fractional index, for example
    ///   an empty text, the legacy Rust ordinal `a0`, or uppercase hex.
    init(parsing text: String) throws(KanbanError) {
        guard let bytes = Self.bytes(ofHex: text), bytes.last == Self.terminator else {
            throw .invalidOrdinal(ordinal: text)
        }
        self.bytes = bytes
    }

    /// Makes an ordinal that sorts before an other ordinal.
    ///
    /// - Parameter upper: The ordinal that the new ordinal sorts before.
    init(before upper: Ordinal) {
        self.init(unterminated: Self.bytes(before: upper.bytes[...]))
    }

    /// Makes an ordinal that sorts after an other ordinal.
    ///
    /// - Parameter lower: The ordinal that the new ordinal sorts after.
    init(after lower: Ordinal) {
        self.init(unterminated: Self.bytes(after: lower.bytes[...]))
    }

    /// Makes an ordinal that sorts between two ordinals.
    ///
    /// When the two ordinals are equal, or when `lower` does not sort before `upper`, there is no ordinal between
    /// them. Then the result is `Ordinal(before: upper)`, the same as in Rust. Thus, the request "put the task
    /// before this neighbor" stays true.
    ///
    /// - Parameters:
    ///   - lower: The ordinal that the new ordinal sorts after.
    ///   - upper: The ordinal that the new ordinal sorts before.
    init(between lower: Ordinal, and upper: Ordinal) {
        guard let bytes = Self.bytes(between: lower.bytes, and: upper.bytes) else {
            self.init(before: upper)
            return
        }
        self.init(unterminated: bytes)
    }

    /// Gives `true` when the first ordinal sorts before the second ordinal.
    ///
    /// - Parameters:
    ///   - lhs: The first ordinal.
    ///   - rhs: The second ordinal.
    /// - Returns: `true` when the bytes of `lhs` come before the bytes of `rhs` in lexicographic order.
    static func < (lhs: Ordinal, rhs: Ordinal) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }
}

// MARK: - Algorithm

extension Ordinal {
    /// Reads the bytes of a lowercase hex text.
    ///
    /// - Parameter text: The hex text.
    /// - Returns: The bytes, or `nil` when the text has a character that is not a lowercase hex digit, or an odd
    ///   number of digits.
    private static func bytes(ofHex text: String) -> [UInt8]? {
        let digitValues = text.utf8.compactMap { code in hexDigits.firstIndex(of: code).map { UInt8($0) } }
        guard digitValues.count == text.utf8.count, digitValues.count.isMultiple(of: hexDigitsPerByte) else {
            return nil
        }
        return stride(from: 0, to: digitValues.count, by: hexDigitsPerByte).map { index in
            (digitValues[index] << bitsPerHexDigit) | digitValues[index + 1]
        }
    }

    /// Gives the bytes, without the ``terminator``, of an ordinal that sorts before the given bytes.
    ///
    /// The first byte that is not zero decides. A byte greater than the ``terminator`` is cut off. A different
    /// byte gets one less, and the bytes after it are cut off.
    ///
    /// - Parameter bytes: Bytes that end with the ``terminator``.
    /// - Returns: The new bytes, without the ``terminator``.
    private static func bytes(before bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard let index = bytes.firstIndex(where: { $0 != .min }) else {
            preconditionFailure("The bytes of an ordinal end with the terminator, so one byte is not zero.")
        }
        let prefix = Array(bytes[..<index])
        return bytes[index] > terminator ? prefix : prefix + [bytes[index] - 1]
    }

    /// Gives the bytes, without the ``terminator``, of an ordinal that sorts after the given bytes.
    ///
    /// The first byte that is not 0xff decides. A byte less than the ``terminator`` is cut off. A different byte
    /// gets one more, and the bytes after it are cut off.
    ///
    /// - Parameter bytes: Bytes that end with the ``terminator``.
    /// - Returns: The new bytes, without the ``terminator``.
    private static func bytes(after bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard let index = bytes.firstIndex(where: { $0 != .max }) else {
            preconditionFailure("The bytes of an ordinal end with the terminator, so one byte is not 0xff.")
        }
        let prefix = Array(bytes[..<index])
        return bytes[index] < terminator ? prefix : prefix + [bytes[index] + 1]
    }

    /// Gives the bytes, without the ``terminator``, of an ordinal that sorts between two ordinals.
    ///
    /// The bytes before the first byte that is different stay. When the two different bytes have a gap of two or
    /// more, the result is the middle of the gap. When the gap is one, the result keeps the lower byte and then
    /// sorts after the rest of `lower`. When one ordinal is a prefix of the other (without its terminator), the
    /// result sorts before or after the rest of the longer ordinal.
    ///
    /// - Parameters:
    ///   - lower: The bytes of the lower ordinal, with the ``terminator``.
    ///   - upper: The bytes of the upper ordinal, with the ``terminator``.
    /// - Returns: The new bytes, or `nil` when the two ordinals are equal or `lower` does not sort before `upper`.
    private static func bytes(between lower: [UInt8], and upper: [UInt8]) -> [UInt8]? {
        let sharedCount = min(lower.count, upper.count) - 1
        for index in 0..<sharedCount {
            let lowerByte = Int(lower[index])
            let upperByte = Int(upper[index])
            if lowerByte + 1 < upperByte {
                let middle = lowerByte + (upperByte - lowerByte) / midpointDivisor
                return Array(lower[..<index]) + [UInt8(middle)]
            }
            if lowerByte + 1 == upperByte {
                return Array(lower[...index]) + bytes(after: lower[(index + 1)...])
            }
            if lowerByte > upperByte {
                return nil
            }
        }
        return bytes(extending: lower, below: upper, sharedCount: sharedCount)
    }

    /// Gives the bytes between two ordinals whose first `sharedCount` bytes are equal.
    ///
    /// - Parameters:
    ///   - lower: The bytes of the lower ordinal, with the ``terminator``.
    ///   - upper: The bytes of the upper ordinal, with the ``terminator``.
    ///   - sharedCount: The number of equal bytes at the start, one less than the length of the shorter ordinal.
    /// - Returns: The new bytes, or `nil` when the two ordinals are equal or `lower` does not sort before `upper`.
    private static func bytes(extending lower: [UInt8], below upper: [UInt8], sharedCount: Int) -> [UInt8]? {
        if lower.count < upper.count {
            guard upper[sharedCount] >= terminator else {
                return nil
            }
            return Array(upper[...sharedCount]) + bytes(before: upper[(sharedCount + 1)...])
        }
        if lower.count > upper.count {
            guard lower[sharedCount] < terminator else {
                return nil
            }
            return Array(lower[...sharedCount]) + bytes(after: lower[(sharedCount + 1)...])
        }
        return nil
    }
}
