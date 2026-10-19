import Testing

@testable import FoundationModelsKanban

/// Tests the shared collection helpers: the first element of each key, and all the values of a list of optionals.
@Suite("Collection helpers")
struct CollectionHelpersTests {
    /// The first element of each key stays, in the order of the first elements, and a later element with the same
    /// key goes away.
    @Test("firstByKey keeps the first element of each key in order")
    func firstByKeyKeepsFirstOfEachKey() {
        let words = ["apple", "banana", "avocado", "cherry", "blueberry"]

        let firsts = words.firstByKey { word in word.first }

        #expect(firsts == ["apple", "banana", "cherry"])
    }

    /// A sequence with no element gives no element.
    @Test("firstByKey of an empty sequence is empty")
    func firstByKeyOfEmptySequence() {
        let firsts = [String]().firstByKey { word in word.count }

        #expect(firsts.isEmpty)
    }

    /// A list with a value in each element gives the values, in the same order.
    @Test("allValues gives each value when no element is nil")
    func allValuesGivesEachValue() {
        let values: [Int?] = [3, 1, 2]

        #expect(values.allValues() == [3, 1, 2])
    }

    /// A list with one `nil` element gives `nil`, not the other values.
    @Test("allValues is nil when one element is nil")
    func allValuesIsNilForOneNil() {
        let values: [Int?] = [3, nil, 2]

        #expect(values.allValues() == nil)
    }

    /// A list with no element gives an empty list, not `nil`.
    @Test("allValues of an empty list is an empty list")
    func allValuesOfEmptyList() {
        let values: [Int?] = []

        #expect(values.allValues() == [])
    }
}
