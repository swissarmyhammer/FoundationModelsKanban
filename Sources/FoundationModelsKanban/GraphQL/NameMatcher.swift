import Foundation

/// A name that the schema has at one position of a document, with the other names that the agent can write for it
/// (plan.md §4.5).
struct CanonicalName: Hashable, Sendable {
    /// The name in the schema, for example `body`.
    let name: String

    /// The other names of the alias table, for example `description` and `desc`. Step 5 of the match uses them.
    let aliases: [String]
}

/// The position of a name in a GraphQL document. The position sets which match steps apply.
enum NamePosition: Sendable {
    /// A field of the `mutation` operation. Only this position gets the word order and the verb synonyms.
    case topLevelMutation

    /// Each other position: a field in a selection, an argument, an `input` field, an enum value, or a root query
    /// field.
    case anyOther
}

/// The result of a name match.
enum NameMatch: Hashable, Sendable {
    /// One step gave exactly one match: the canonical name. It is the same as the name of the agent when the name
    /// is correct.
    case found(canonical: String)

    /// One step gave two or more matches. The tool does not choose one. The matches are in the order of the
    /// candidates.
    case tie(matches: [String])

    /// No step gave a match.
    case notFound
}

/// Matches a wrong name to one canonical name of the schema (plan.md §4.5).
///
/// The match tries the steps of ``MatchStep`` in order, and stops at the first step that gives one or more
/// matches. One match is the result. Two or more matches are a tie, and the matcher does not guess. A mapping of
/// the never list (``NeverMapping/all``) is never made.
enum NameMatcher {
    /// The minimum number of letters of a name for the close spelling step.
    fileprivate static let minimumCloseSpellingLength = 4

    /// The verb synonyms of a top-level mutation: each synonym and its canonical verb. These are the Rust verb
    /// aliases, with `archive` mapped to `delete` and `unarchive` mapped to `undelete` (plan.md §12, item 21). The
    /// Rust alias `create` → `init` is not here: `create` maps to `add`.
    fileprivate static let verbSynonyms: [String: String] = [
        "create": "add", "new": "add", "insert": "add",
        "remove": "delete", "rm": "delete", "del": "delete", "archive": "delete",
        "edit": "update", "modify": "update", "set": "update", "patch": "update",
        "mv": "move",
        "done": "complete", "finish": "complete", "close": "complete",
        "label": "tag", "unlabel": "untag",
        "restore": "undelete", "unarchive": "undelete", "recover": "undelete",
    ]

    /// Gives the canonical name for a name of the agent.
    ///
    /// - Parameters:
    ///   - name: The name that the agent wrote, for example `taskAdd`.
    ///   - candidates: The valid names at the position of the name, each with its aliases.
    ///   - position: The position of the name in the document.
    /// - Returns: The canonical name, the tie of the first step with two or more matches, or ``NameMatch/notFound``.
    static func match(
        for name: String,
        among candidates: [CanonicalName],
        at position: NamePosition
    ) -> NameMatch {
        let query = NameQuery(name: name, position: position)
        for step in MatchStep.allCases {
            let matches = candidates
                .filter { step.isMatch(of: $0, for: query) && !query.isForbidden(mappingTo: $0) }
                .map(\.name)
            guard let first = matches.first else {
                continue
            }
            return matches.count == 1 ? .found(canonical: first) : .tie(matches: matches)
        }
        return .notFound
    }
}

/// A mapping that the matcher must not make: a word of the agent that must not become a different word.
///
/// For example, `create` never maps to `init`, so `createBoard` never gives `initBoard`.
private struct NeverMapping {
    /// The never list: the mappings that the matcher must not make, at each step after the exact name.
    static let all = [NeverMapping(agentWord: "create", canonicalWord: "init")]

    /// The word in the name of the agent, for example `create`.
    let agentWord: String

    /// The word in the canonical name that the agent word must not become, for example `init`.
    let canonicalWord: String

    /// Tells if the mapping changes the agent word to the canonical word.
    ///
    /// A mapping that keeps the agent word, or a name that already has the canonical word, is not changed by the
    /// rule.
    ///
    /// - Parameters:
    ///   - input: The words of the name of the agent.
    ///   - candidate: The words of the canonical name.
    /// - Returns: `true` when the match must not be made.
    func forbids(from input: NameWords, to candidate: NameWords) -> Bool {
        input.words.contains(agentWord) && !input.words.contains(canonicalWord)
            && candidate.words.contains(canonicalWord) && !candidate.words.contains(agentWord)
    }
}

// MARK: - Match steps

/// The match steps of plan.md §4.5, in the order that the matcher tries them.
private enum MatchStep: CaseIterable {
    /// Step 1: the exact name.
    case exact

    /// Step 2: the same words in each case and style: `camelCase`, `snake_case`, `kebab-case`, and any letter case.
    case caseAndStyle

    /// Step 3: the singular or plural form of the last word.
    case number

    /// Step 4: for a top-level mutation, the other word order and the verb synonyms.
    case wordOrderAndSynonyms

    /// Step 5: the alias table of the candidate.
    case alias

    /// Step 6: one changed, added, or removed letter, for a name of ``NameMatcher/minimumCloseSpellingLength`` or
    /// more letters.
    case closeSpelling

    /// Tells if the step matches a candidate to the name.
    ///
    /// - Parameters:
    ///   - candidate: The valid name, with its aliases.
    ///   - query: The name of the agent.
    /// - Returns: `true` when the step gives the candidate for the name.
    func isMatch(of candidate: CanonicalName, for query: NameQuery) -> Bool {
        let candidateKey = NameWords(splitting: candidate.name).key
        switch self {
        case .exact:
            return candidate.name == query.name
        case .caseAndStyle:
            return candidateKey == query.words.key
        case .number:
            return query.numberKeys.contains(candidateKey)
        case .wordOrderAndSynonyms:
            return query.mutationKeys.contains(candidateKey)
        case .alias:
            return candidate.aliases.contains { NameWords(splitting: $0).key == query.words.key }
        case .closeSpelling:
            return query.words.key.count >= NameMatcher.minimumCloseSpellingLength
                && query.words.key.differsByOneLetter(from: candidateKey)
        }
    }
}

/// The name of the agent, with the forms that the match steps compare.
private struct NameQuery {
    /// The name as the agent wrote it.
    let name: String

    /// The words of the name.
    let words: NameWords

    /// The keys of the singular and plural forms of the name.
    let numberKeys: Set<String>

    /// The keys of the verbNoun forms of the name with the canonical verbs. The set is empty when the name is not
    /// a top-level mutation.
    let mutationKeys: Set<String>

    /// Makes the query of a name.
    ///
    /// - Parameters:
    ///   - name: The name as the agent wrote it.
    ///   - position: The position of the name in the document.
    init(name: String, position: NamePosition) {
        let words = NameWords(splitting: name)
        self.name = name
        self.words = words
        numberKeys = Set(words.numberVariants.map(\.key))
        switch position {
        case .topLevelMutation:
            mutationKeys = Set(words.mutationVariants.map(\.key))
        case .anyOther:
            mutationKeys = []
        }
    }

    /// Tells if a mapping of the never list forbids the match of the name to a candidate.
    ///
    /// - Parameter candidate: The valid name.
    /// - Returns: `true` when the match must not be made.
    func isForbidden(mappingTo candidate: CanonicalName) -> Bool {
        let candidateWords = NameWords(splitting: candidate.name)
        return NeverMapping.all.contains { $0.forbids(from: words, to: candidateWords) }
    }
}

// MARK: - Words of a name

/// The words of a name, in lowercase. `addTask`, `add_task`, `add-task`, and `ADD_TASK` give the same words.
private struct NameWords {
    /// The rules that change the number of a word: a suffix, and the text that replaces it. The empty suffix
    /// matches each word. Each rule that matches gives one form, so a word can get more than one form.
    static let numberRules: [(suffix: String, replacement: String)] = [
        ("ies", "y"), ("es", ""), ("s", ""),
        ("y", "ies"), ("s", "ses"), ("x", "xes"), ("ch", "ches"), ("sh", "shes"), ("", "s"),
    ]

    /// The words, in lowercase.
    let words: [String]

    /// The words joined with no separator, for example `addtask`. Two names with the same key differ only in case
    /// and style.
    var key: String {
        words.joined()
    }

    /// The forms of the name with the last word in the singular or the plural, for example `tag` for `tags`.
    var numberVariants: [NameWords] {
        guard let last = words.last else {
            return []
        }
        let leadingWords = Array(words.dropLast())
        return Self.numberRules
            .filter { last.hasSuffix($0.suffix) }
            .map { NameWords(words: leadingWords + [String(last.dropLast($0.suffix.count)) + $0.replacement]) }
    }

    /// The forms of a mutation name in the verbNoun order, with the verb synonym changed to the canonical verb, and
    /// the number forms of each. The two orders are the words as they are (verbNoun) and the last word first
    /// (nounVerb to verbNoun).
    var mutationVariants: [NameWords] {
        guard let last = words.last else {
            return []
        }
        let orders = [words, [last] + words.dropLast()]
        let verbNoun = orders.map { order in
            NameWords(words: order.prefix(1).map { NameMatcher.verbSynonyms[$0] ?? $0 } + order.dropFirst())
        }
        return verbNoun + verbNoun.flatMap(\.numberVariants)
    }
}

extension NameWords {
    /// Splits a name into its words.
    ///
    /// A character that is not a letter or a digit separates two words. In each part, an uppercase letter after a
    /// lowercase letter or a digit starts a word, and so does the last uppercase letter of a run before a lowercase
    /// letter (`IDList` gives `id` and `list`). A name in all uppercase is one word.
    ///
    /// - Parameter name: The name, for example `shortId` or `short_id`.
    init(splitting name: String) {
        words = name
            .split { !($0.isLetter || $0.isNumber) }
            .flatMap { Self.camelCaseWords(in: Array($0)) }
            .map { $0.lowercased() }
    }

    /// Splits a part of a name with no separator at each camel case word start.
    ///
    /// - Parameter characters: The characters of the part. The part is not empty.
    /// - Returns: The words of the part, in their case.
    private static func camelCaseWords(in characters: [Character]) -> [String] {
        let starts = [0] + characters.indices.dropFirst().filter { startsWord(at: $0, in: characters) }
        return zip(starts, starts.dropFirst() + [characters.count]).map { String(characters[$0..<$1]) }
    }

    /// Tells if the character at an index starts a camel case word.
    ///
    /// - Parameters:
    ///   - index: The index of the character. It is not the first index.
    ///   - characters: The characters of the part of the name.
    /// - Returns: `true` when the character is an uppercase letter after a character that is not uppercase, or the
    ///   last uppercase letter of a run before a lowercase letter.
    private static func startsWord(at index: Int, in characters: [Character]) -> Bool {
        guard characters[index].isUppercase else {
            return false
        }
        guard characters[index - 1].isUppercase else {
            return true
        }
        let next = index + 1
        return next < characters.count && characters[next].isLowercase
    }
}

extension String {
    /// Tells if the text differs from a different text by exactly one changed, added, or removed character.
    ///
    /// - Parameter other: The other text.
    /// - Returns: `true` when one edit changes one text to the other. Two equal texts give `false`.
    fileprivate func differsByOneLetter(from other: String) -> Bool {
        let lhs = Array(self)
        let rhs = Array(other)
        if lhs.count == rhs.count {
            return zip(lhs, rhs).filter { $0 != $1 }.count == 1
        }
        let (shorter, longer) = lhs.count < rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard longer.count == shorter.count + 1 else {
            return false
        }
        let index = shorter.indices.first { shorter[$0] != longer[$0] } ?? shorter.count
        return shorter[index...] == longer[(index + 1)...]
    }
}
