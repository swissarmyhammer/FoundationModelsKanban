import FoundationModelsKanban
import Testing

/// Tests that the package builds and that the test target can link the library.
@Suite("Scaffold")
struct ScaffoldTests {
    /// The library logger has the module name as its label, so that a host
    /// backend can select the records of this package.
    @Test("The library logger has the module name as its label")
    func libraryLoggerHasTheModuleLabel() {
        #expect(Log.kanban.label == "FoundationModelsKanban")
    }
}
