import OrderedCollections

extension Sequence {
    /// Keeps the first element of each key, in the order of the first elements. A later element with the same key
    /// goes away.
    ///
    /// A call that names one board with two refs uses it, so that the call reads or writes the board one time.
    ///
    /// - Parameter key: The key of an element.
    /// - Returns: The first element of each key.
    /// - Throws: The error of `key`.
    func firstByKey<Key: Hashable>(_ key: (Element) throws -> Key) rethrows -> [Element] {
        let firsts = OrderedDictionary(
            try map { element in (try key(element), element) },
            uniquingKeysWith: { first, _ in first }
        )
        return Array(firsts.values)
    }
}

extension Array {
    /// Gives all the values of a list of optionals, or `nil` when one element is `nil`.
    ///
    /// A step that must read each board of a call uses it: a board that the engine did not load yet makes the whole
    /// result `nil`, and the call runs again after the load.
    ///
    /// - Returns: The values, in the order of the elements, or `nil` when one element is `nil`. An empty list gives an
    ///   empty list.
    func allValues<Wrapped>() -> [Wrapped]? where Element == Wrapped? {
        let values = compactMap(\.self)
        return values.count == count ? values : nil
    }
}
