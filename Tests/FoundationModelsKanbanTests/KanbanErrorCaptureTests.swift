import Testing

@testable import FoundationModelsKanban

/// Tests that ``KanbanErrorCapture`` gives the error that the call throws.
@Suite("Kanban error capture")
struct KanbanErrorCaptureTests {
    /// The error that the call of the test throws.
    static let thrown = KanbanError.multilineChecklistItemText(text: "one\ntwo")

    /// Throws ``thrown``.
    ///
    /// - Throws: ``thrown``, each time.
    static func throwError() throws {
        throw thrown
    }

    @Test("The capture gives the KanbanError that the call throws")
    func captureGivesThrownError() throws {
        let error = try KanbanErrorCapture.error { try Self.throwError() }
        #expect(error == Self.thrown)
    }
}
