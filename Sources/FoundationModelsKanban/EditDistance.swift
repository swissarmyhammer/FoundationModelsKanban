import Foundation

extension String {
    /// Gives the edit distance from this text to a different text: the least number of inserts, deletes, and
    /// substitutions of one character that change this text to the other text (the Levenshtein distance).
    ///
    /// The name check of a filter uses it to find the nearest name of the board (divergence.md §17). The compare
    /// reads characters, and it does not ignore case.
    ///
    /// - Parameter target: The other text.
    /// - Returns: The edit distance. Two equal texts give 0, and an empty text gives the length of the other text.
    func editDistance(to target: String) -> Int {
        let targetCharacters = Array(target)
        // `previous[offset]` is the distance from the part of this text before the current character to the first
        // `offset` characters of the target.
        var previous = Array(0...targetCharacters.count)
        for (index, character) in enumerated() {
            var current = [index + 1]
            for (offset, targetCharacter) in targetCharacters.enumerated() {
                let substitution = previous[offset] + (character == targetCharacter ? 0 : 1)
                current.append(Swift.min(substitution, previous[offset + 1] + 1, current[offset] + 1))
            }
            previous = current
        }
        return previous[targetCharacters.count]
    }
}
