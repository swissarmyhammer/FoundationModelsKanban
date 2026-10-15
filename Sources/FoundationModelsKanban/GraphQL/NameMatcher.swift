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
    /// A field of the `mutation` operation. This position gets the word order and the verb synonyms of a mutation.
    case topLevelMutation

    /// A field at the root of a `query` operation, or of a fragment on the query type. This position gets the word
    /// order and the query verbs (divergence.md Q10).
    case topLevelQuery

    /// Each other position: a field in a selection, an argument, an `input` field, or an enum value.
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
/// matches. One match is the result. Two or more matches are a tie, and the matcher does not guess.
enum NameMatcher {
    /// The minimum number of letters of a name for the close spelling step.
    fileprivate static let minimumCloseSpellingLength = 4

    /// The verb synonyms of a top-level mutation: each synonym and its canonical verb. These are the Rust verb
    /// aliases, with `archive` mapped to `delete` and `unarchive` mapped to `undelete` (plan.md §12, item 21). The
    /// Rust alias `create` → `init` is in ``nounVerbSynonyms``, for the noun `board` only.
    fileprivate static let verbSynonyms: [String: String] = [
        "create": "add", "new": "add", "insert": "add",
        "remove": "delete", "rm": "delete", "del": "delete", "archive": "delete",
        "edit": "update", "modify": "update", "set": "update", "patch": "update",
        "mv": "move",
        "done": "complete", "finish": "complete", "close": "complete",
        "label": "tag", "unlabel": "untag",
        "restore": "undelete", "unarchive": "undelete", "recover": "undelete",
    ]

    /// The verb synonyms of a top-level mutation for one noun, by the noun in the singular. For the noun, they apply
    /// before ``verbSynonyms``. The schema has `initBoard` and no `addBoard`, so `createBoard` and `newBoard` give
    /// `initBoard` (divergence.md Q11).
    fileprivate static let nounVerbSynonyms: [String: [String: String]] = [
        "board": ["create": "init", "new": "init"],
    ]

    /// The verbs of a root query field, by the verb (divergence.md Q10). `get`, `show`, `read`, and `fetch` give
    /// the singular field of the noun, `list`, `find`, and `query` give the plural field, and `search` and `next`
    /// give `searchTasks` and `nextTask`.
    fileprivate static let queryVerbs: [String: QueryVerb] = [
        "get": .singular, "show": .singular, "read": .singular, "fetch": .singular,
        "list": .plural, "find": .plural, "query": .plural,
        "search": QueryVerb(fieldWords: ["search"], defaultNoun: ["task"], number: .plural),
        "next": QueryVerb(fieldWords: ["next"], defaultNoun: ["task"], number: .singular),
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
            let matches = step.matches(among: candidates, for: query)
            guard let first = matches.first else {
                continue
            }
            return matches.count == 1 ? .found(canonical: first) : .tie(matches: matches)
        }
        return .notFound
    }
}

// MARK: - Query verbs

/// A verb of a root query field: how the noun after the verb gives the name of the field (divergence.md Q10).
private struct QueryVerb {
    /// A verb that gives the singular field of the noun, for example `get` in `getTask`.
    static let singular = QueryVerb(fieldWords: [], defaultNoun: [], number: .singular)

    /// A verb that gives the plural field of the noun, for example `list` in `listTasks`.
    static let plural = QueryVerb(fieldWords: [], defaultNoun: [], number: .plural)

    /// The words of the verb that the field name keeps, for example `search` in `searchTasks`. The list is empty
    /// when the field name is the noun alone.
    let fieldWords: [String]

    /// The noun when the agent wrote the verb with no noun, for example `task` for `next`. The list is empty when
    /// the verb needs a noun.
    let defaultNoun: [String]

    /// The number of the noun that the verb tries first.
    let number: NounNumber

    /// Gives the forms of the field name for a noun, in tiers: the step tries each tier in order.
    ///
    /// - Parameter noun: The words after the verb, as the agent wrote them. The list can be empty.
    /// - Returns: The tiers of ``NounNumber/tiers(of:)``, or no tier when the verb has no noun.
    func tiers(forNoun noun: [String]) -> [[NameWords]] {
        let written = noun.isEmpty ? defaultNoun : noun
        guard !written.isEmpty else {
            return []
        }
        return number.tiers(of: NameWords(words: fieldWords + written))
    }
}

/// The number of a noun that a query verb asks for.
private enum NounNumber {
    /// The singular: `getTasks` gives `task`.
    case singular

    /// The plural: `listTask` gives `tasks`.
    case plural

    /// Gives the forms of a field name in the order that the verb tries them: the asked number, the name as the
    /// agent wrote it, then the other number. When the field of the asked number does not exist, the other number
    /// gives the field that holds the noun, for example `columns` for `showColumn`.
    ///
    /// - Parameter field: The field name with the noun as the agent wrote it.
    /// - Returns: Three tiers of forms.
    func tiers(of field: NameWords) -> [[NameWords]] {
        switch self {
        case .singular:
            [field.singularVariants, [field], field.pluralVariants]
        case .plural:
            [field.pluralVariants, [field], field.singularVariants]
        }
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

    /// Step 4: for a top-level mutation, the other word order and the verb synonyms; for a root query field, the
    /// other word order and the query verbs.
    case wordOrderAndSynonyms

    /// Step 5: the alias table of the candidate.
    case alias

    /// Step 6: one changed, added, or removed letter, for a name of ``NameMatcher/minimumCloseSpellingLength`` or
    /// more letters.
    case closeSpelling

    /// Gives the candidates that the step matches to the name: the matches of the first pass of the step that
    /// matches one or more candidates.
    ///
    /// - Parameters:
    ///   - candidates: The valid names, with their aliases.
    ///   - query: The name of the agent.
    /// - Returns: The names of the matched candidates, in the order of the candidates. The list is empty when no
    ///   pass matches.
    func matches(among candidates: [CanonicalName], for query: NameQuery) -> [String] {
        passes(for: query).lazy
            .map { isMatch in candidates.filter(isMatch).map(\.name) }
            .first { matches in !matches.isEmpty } ?? []
    }

    /// Gives the passes of the step, in the order that the step tries them. Each pass tells if it matches a
    /// candidate. Step 4 has one pass for each key tier of the name; each other step has one pass.
    ///
    /// - Parameter query: The name of the agent.
    /// - Returns: The passes.
    private func passes(for query: NameQuery) -> [(CanonicalName) -> Bool] {
        switch self {
        case .exact:
            [{ candidate in candidate.name == query.name }]
        case .caseAndStyle:
            [{ candidate in candidate.key == query.words.key }]
        case .number:
            [{ candidate in query.numberKeys.contains(candidate.key) }]
        case .wordOrderAndSynonyms:
            query.verbKeyTiers.map { tier in { candidate in tier.contains(candidate.key) } }
        case .alias:
            [{ candidate in
                candidate.aliases.contains { alias in NameWords(splitting: alias).key == query.words.key }
            }]
        case .closeSpelling:
            [{ candidate in
                query.words.key.count >= NameMatcher.minimumCloseSpellingLength
                    && query.words.key.differsByOneLetter(from: candidate.key)
            }]
        }
    }
}

extension CanonicalName {
    /// The key of the words of the name, for example `addtask` for `addTask`.
    fileprivate var key: String {
        NameWords(splitting: name).key
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

    /// The keys of step 4, in tiers that the step tries in order. A top-level mutation has one tier: the verbNoun
    /// forms with the canonical verbs. A root query field has the tiers of its query verb. Each other position has
    /// no tier.
    let verbKeyTiers: [Set<String>]

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
        verbKeyTiers = switch position {
        case .topLevelMutation:
            [Set(words.mutationVariants.map(\.key))]
        case .topLevelQuery:
            words.queryKeyTiers
        case .anyOther:
            []
        }
    }
}

// MARK: - Words of a name

/// The words of a name, in lowercase. `addTask`, `add_task`, `add-task`, and `ADD_TASK` give the same words.
private struct NameWords {
    /// A rule that changes the number of a word: a suffix, and the text that replaces it. The empty suffix matches
    /// each word.
    typealias NumberRule = (suffix: String, replacement: String)

    /// The rules that give the singular of a word.
    static let singularRules: [NumberRule] = [("ies", "y"), ("es", ""), ("s", "")]

    /// The rules that give the plural of a word.
    static let pluralRules: [NumberRule] = [
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
        variants(by: Self.singularRules + Self.pluralRules)
    }

    /// The forms of the name with the last word in the singular, for example `task` for `tasks`.
    var singularVariants: [NameWords] {
        variants(by: Self.singularRules)
    }

    /// The forms of the name with the last word in the plural, for example `columns` for `column`.
    var pluralVariants: [NameWords] {
        variants(by: Self.pluralRules)
    }

    /// The two word orders of the name: the words as they are, and the last word first (nounVerb to verbNoun).
    var orders: [[String]] {
        words.last.map { last in [words, [last] + words.dropLast()] } ?? []
    }

    /// The forms of a mutation name in the verbNoun order, with the verb synonym changed to the canonical verb, and
    /// the number forms of each, in the two ``orders``.
    var mutationVariants: [NameWords] {
        let verbNoun = orders.map { order in
            let noun = Array(order.dropFirst())
            let verb = order.prefix(1).map { verb in Self.canonicalVerb(of: verb, before: noun) }
            return NameWords(words: verb + noun)
        }
        return verbNoun + verbNoun.flatMap(\.numberVariants)
    }

    /// The keys of a root query field name with a query verb, in the tiers of ``QueryVerb/tiers(forNoun:)``. Each
    /// tier holds the forms of the two ``orders``. A name with no query verb has no tier.
    var queryKeyTiers: [Set<String>] {
        let tiersOfEachOrder = orders.map(Self.queryTiers(of:))
        let tierCount = tiersOfEachOrder.map(\.count).max() ?? 0
        return (0..<tierCount).map { index in
            Set(tiersOfEachOrder.flatMap { tiers in tiers.indices.contains(index) ? tiers[index].map(\.key) : [] })
        }
    }

    /// Gives the forms of a field name for words that start with a query verb. When the words after the verb start
    /// with a query verb too, that verb gives the forms, so `getNext` gives the forms of `next`.
    ///
    /// - Parameter words: The words in one order.
    /// - Returns: The tiers of forms, or no tier when the first word is not a query verb.
    private static func queryTiers(of words: [String]) -> [[NameWords]] {
        guard let verb = words.first.flatMap({ word in NameMatcher.queryVerbs[word] }) else {
            return []
        }
        let noun = Array(words.dropFirst())
        let innerTiers = queryTiers(of: noun)
        return innerTiers.isEmpty ? verb.tiers(forNoun: noun) : innerTiers
    }

    /// Gives the canonical verb of a mutation verb before a noun: the synonym for the noun, else the synonym of
    /// ``NameMatcher/verbSynonyms``, else the verb.
    ///
    /// - Parameters:
    ///   - verb: The first word of the name.
    ///   - noun: The words after the verb.
    /// - Returns: The canonical verb, for example `init` for `create` before `board`.
    private static func canonicalVerb(of verb: String, before noun: [String]) -> String {
        let nounWords = NameWords(words: noun)
        let nounKeys = [nounWords.key] + nounWords.numberVariants.map(\.key)
        let nounSynonym = nounKeys.lazy.compactMap { key in NameMatcher.nounVerbSynonyms[key]?[verb] }.first
        return nounSynonym ?? NameMatcher.verbSynonyms[verb] ?? verb
    }

    /// Gives the forms of the name with the last word changed by each rule whose suffix the word has. Each rule
    /// that matches gives one form, so a word can get more than one form.
    ///
    /// - Parameter rules: The number rules.
    /// - Returns: The forms, in the order of the rules.
    private func variants(by rules: [NumberRule]) -> [NameWords] {
        guard let last = words.last else {
            return []
        }
        let leadingWords = Array(words.dropLast())
        return rules
            .filter { rule in last.hasSuffix(rule.suffix) }
            .map { rule in
                NameWords(words: leadingWords + [String(last.dropLast(rule.suffix.count)) + rule.replacement])
            }
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
