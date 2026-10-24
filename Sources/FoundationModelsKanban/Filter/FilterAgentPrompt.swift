import Foundation

/// The system prompt of the filter agent (divergence.md §17, "A smart prompt"): the resource `FilterAgentPrompt.md` of
/// the package, not text in the code.
///
/// The prompt holds the grammar of the filter language, a table of each virtual tag of ``VirtualTag/allCases``, the
/// rules of the default selection, and examples. An example is a line that starts with ``englishLabel``, with a line
/// that starts with ``filterLabel`` directly after it. The unit tests parse each example statement and run the name
/// check on it, so an example cannot go out of date. The engine adds the vocabulary of the board after the prompt.
struct FilterAgentPrompt: Sendable {
    /// One example of the prompt: an English text, and the filter statement that the filter agent writes for it.
    struct Example: Sendable, Equatable {
        /// The English text, as a person types it.
        let english: String

        /// The filter statement for the text.
        let filter: String
    }

    /// The name of the resource file, with no extension.
    static let resourceName = "FilterAgentPrompt"

    /// The extension of the resource file.
    static let resourceExtension = "md"

    /// The start of the line of an example that holds the English text.
    static let englishLabel = "English: "

    /// The start of the line of an example that holds the filter statement. It is the line after the English line.
    static let filterLabel = "Filter: "

    /// The full text of the prompt.
    let text: String

    /// Each example of the prompt, in text order: each English line that has a filter line directly after it.
    var examples: [Example] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return zip(lines, lines.dropFirst()).compactMap { english, filter in
            guard english.hasPrefix(Self.englishLabel), filter.hasPrefix(Self.filterLabel) else {
                return nil
            }
            return Example(
                english: String(english.dropFirst(Self.englishLabel.count)),
                filter: String(filter.dropFirst(Self.filterLabel.count))
            )
        }
    }

    /// Reads the prompt from the resource bundle of the package.
    ///
    /// - Returns: The prompt.
    /// - Throws: `CocoaError.fileReadNoSuchFile` when the bundle has no prompt resource, or the error of the read.
    static func load() throws -> FilterAgentPrompt {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return FilterAgentPrompt(text: try String(contentsOf: url, encoding: .utf8))
    }
}
