import Testing

@testable import FoundationModelsKanban

/// Tests the case tests of ``FieldUpdate``: `isCleared`, `isUnchanged`, and `value`.
@Suite("Field update cases")
struct FieldUpdateTests {
    /// The new value of a changed field in the tests.
    static let newValue = "do"

    /// Each update with the expected `isCleared`, `isUnchanged`, and `value`.
    static let cases: [(FieldUpdate<String>, Bool, Bool, String?)] = [
        (.unchanged, false, true, nil),
        (.cleared, true, false, nil),
        (.changed(newValue), false, false, newValue),
    ]

    /// Each case of an update gives the correct result for each case test.
    @Test("Each case test reads only its case", arguments: cases)
    func caseTestsReadTheirCase(update: FieldUpdate<String>, isCleared: Bool, isUnchanged: Bool, value: String?) {
        #expect(update.isCleared == isCleared)
        #expect(update.isUnchanged == isUnchanged)
        #expect(update.value == value)
    }
}
