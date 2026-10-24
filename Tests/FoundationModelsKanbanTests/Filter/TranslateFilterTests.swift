import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the engine part of the filter agent (divergence.md §17): the query `translateFilter` and the filter model of
/// the engine.
///
/// A text that is a filter of the board comes back with `attempts: 0`, and the filter model gets no call. A text that
/// is not a filter of the board goes to the loop of the filter model (``FilterAgentLoopTests`` tests the loop). With no
/// model, the query gives `FILTER_MODEL_MISSING`. The query writes nothing: no event, so also no undo entry, because
/// the undo log reads only the events. Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column
/// `todo`, and one task in `todo`. No test needs a real model: ``SpyLanguageModel`` gives the scripted answers and
/// records each call.
@Suite("translateFilter: the engine part of the filter agent", .watcherBudget)
struct TranslateFilterTests {
    /// A filter of the fixture board: the tasks in `todo` that are not done.
    private static let fixtureFilter = "%todo !#DONE"

    /// English text, which is not a filter.
    private static let englishText = "bugs that alice has not finished"

    /// The first word of ``englishText``: the parser stops there.
    private static let englishFirstWord = "bugs"

    /// A column atom with a name one letter from the column `todo` of the fixture board.
    private static let misspelledColumn = "%todoo"

    // MARK: - Helpers

    /// Makes a query document with one `translateFilter` field that reads each field of the result.
    ///
    /// - Parameter text: The text to translate.
    /// - Returns: The document.
    private static func translation(of text: String) -> String {
        #"{ translateFilter(text: "\#(text)") { attempts filter message } }"#
    }

    // MARK: - A text that is a filter

    @Test("A text that is a filter of the board comes back with attempts 0, writes nothing, and calls no model")
    func filterComesBackWithNoModelCall() async throws {
        let directory = try TemporaryDirectory()
        let model = SpyLanguageModel()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: Self.translation(of: Self.fixtureFilter),
            filteringWith: model,
            in: directory
        )
        let translation = #"{"attempts":0,"filter":"\#(Self.fixtureFilter)","message":null}"#
        #expect(response == #"{"data":{"translateFilter":\#(translation)}}"#)
        #expect(model.calls.count == 0)
    }

    // MARK: - A text that is not a filter

    @Test("English text with no filter model gives FILTER_MODEL_MISSING with the parse error, and writes nothing")
    func englishWithNoModelGivesModelMissing() async throws {
        let directory = try TemporaryDirectory()
        let parseError = KanbanError.invalidFilter(
            filter: Self.englishText,
            position: try FilterParserTests.position(of: Self.englishFirstWord, in: Self.englishText),
            detail: FilterParserTests.notATermDetail(for: Self.englishFirstWord),
            example: FilterParserTests.operatorExample
        )
        let error = try await ColumnActorTests.failure(of: Self.translation(of: Self.englishText), in: directory)
        #expect(error == .filterModelMissing(filterError: parseError))
    }

    @Test("A name that names nothing, with no filter model, gives FILTER_MODEL_MISSING with the name error")
    func unknownNameWithNoModelGivesModelMissing() async throws {
        let directory = try TemporaryDirectory()
        let nameError = try FilterNameCheckTests.unknownName(
            in: Self.misspelledColumn,
            at: Self.misspelledColumn,
            detail: "no column named `todoo`; the nearest column is `todo`",
            example: "%todo"
        )
        let error = try await ColumnActorTests.failure(of: Self.translation(of: Self.misspelledColumn), in: directory)
        #expect(error == .filterModelMissing(filterError: nameError))
    }

    @Test("With a filter model, English text gives the statement of the model with attempts 1, and writes nothing")
    func englishWithModelGivesStatementOfModel() async throws {
        let directory = try TemporaryDirectory()
        let model = SpyLanguageModel(answers: [.text(Self.fixtureFilter)])
        let response = try await ColumnActorTests.respondWritingNothing(
            to: Self.translation(of: Self.englishText),
            filteringWith: model,
            in: directory
        )
        let translation = #"{"attempts":1,"filter":"\#(Self.fixtureFilter)","message":null}"#
        #expect(response == #"{"data":{"translateFilter":\#(translation)}}"#)
        #expect(model.calls.recorded.map(\.prompts) == [[Self.englishText]])
    }
}
