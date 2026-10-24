import Foundation
import FoundationModelsExtras

/// The trigger of a column: the skill that runs when a task enters the column, and if the task then moves to the next
/// column (divergence.md §22, TestudoApp KANBAN-2 and D47).
///
/// The configuration is the YAML frontmatter at the top of the column body: `trigger: <skill>` and `next: <bool>`.
/// Thus it is in the event log, with history, undo, and git merge, and it has no file and no stored property of its
/// own. A body with no frontmatter gives no skill and `next: true`. A frontmatter that does not give a valid value
/// gives the default of that value and a ``Problem``, and a write that leaves the problem gives a warning. A bad
/// frontmatter never stops a write.
///
/// This package does not run the trigger. The `TriggerRunner` of TestudoApp KANBAN-1 reads it.
struct ColumnTrigger: Equatable, Sendable {
    /// Why the frontmatter of a body does not give a valid value.
    enum Problem: Error, Equatable, Sendable {
        /// The frontmatter is not valid YAML. The line is the line of the body, when the parser gives it.
        case invalidYAML(line: Int?)

        /// The frontmatter is valid YAML, but it is not a mapping of keys, for example a list.
        case notAMapping

        /// The value of the key is not a value of its type: a `trigger` that is not text, or a `next` that is not
        /// true or false.
        case invalidValue(key: String)
    }

    /// The frontmatter key of the skill.
    static let triggerKey = "trigger"

    /// The frontmatter key that tells if the task moves to the next column when the skill ends.
    static let nextKey = "next"

    /// The code of the warning of a write that leaves a column body with a ``Problem``.
    static let warningCode = "INVALID_COLUMN_FRONTMATTER"

    /// The `next` value of a body that does not give one: the task moves to the next column (TestudoApp D29).
    static let defaultMovesToNext = true

    /// The fence line that opens and closes a frontmatter.
    private static let fence = "---"

    /// The number of lines of the body before the first line of the frontmatter: the opening fence line.
    private static let linesBeforeFrontmatter = 1

    /// The text forms of `next` that a forgiving read accepts, in lowercase, with the value of each form. A YAML
    /// boolean needs no form: this table reads a `next` that the frontmatter gives in quotes.
    private static let nextWords = [
        "true": true, "yes": true, "on": true,
        "false": false, "no": false, "off": false,
    ]

    /// The skill that runs when a task enters the column, or `nil` for no trigger.
    let skill: String?

    /// `true` when the task moves to the next column when the skill ends.
    let movesToNext: Bool

    /// Why the frontmatter does not give a valid value, or `nil` when each value is valid.
    let problem: Problem?

    /// Makes a trigger from its values.
    ///
    /// - Parameters:
    ///   - skill: The skill, or `nil` for no trigger.
    ///   - movesToNext: `true` when the task moves to the next column when the skill ends.
    ///   - problem: Why the frontmatter does not give a valid value, or `nil`.
    init(skill: String?, movesToNext: Bool, problem: Problem?) {
        self.skill = skill
        self.movesToNext = movesToNext
        self.problem = problem
    }

    /// Reads the trigger from the frontmatter of a column body.
    ///
    /// - Parameter body: The Markdown body of the column.
    init(body: String) {
        guard let frontmatter = FrontmatterDocument.split(text: body).frontmatter else {
            self.init(skill: nil, movesToNext: Self.defaultMovesToNext, problem: nil)
            return
        }
        switch Self.parse(frontmatter) {
        case .success(let keys):
            self.init(keys: keys)
        case .failure(let problem):
            self.init(skill: nil, movesToNext: Self.defaultMovesToNext, problem: problem)
        }
    }

    /// Reads the trigger from the keys of a frontmatter. A value that is not valid gives its default, and the problem
    /// of the first such value.
    ///
    /// - Parameter keys: The keys of the frontmatter.
    private init(keys: [String: YAMLValue]) {
        let skill = Self.skill(of: keys[Self.triggerKey])
        let next = Self.movesToNext(of: keys[Self.nextKey])
        let checks = [(skill.isValid, Self.triggerKey), (next.isValid, Self.nextKey)]
        let badKey = checks.first { isValid, _ in !isValid }?.1
        self.init(skill: skill.value, movesToNext: next.value, problem: badKey.map(Problem.invalidValue(key:)))
    }

    /// Parses a frontmatter text as a mapping of keys.
    ///
    /// - Parameter frontmatter: The text between the two fence lines.
    /// - Returns: The keys, or the problem of the text. An empty frontmatter has no key.
    private static func parse(_ frontmatter: String) -> Result<[String: YAMLValue], Problem> {
        let value: YAMLValue
        do {
            value = try YAMLValue.parse(frontmatter)
        } catch YAMLValueParsingError.malformed(let line, _) {
            return .failure(.invalidYAML(line: line.map { line in line + linesBeforeFrontmatter }))
        } catch {
            return .failure(.invalidYAML(line: nil))
        }
        switch value {
        case .dictionary(let keys): return .success(keys)
        case .null: return .success([:])
        case .string, .int, .double, .bool, .array: return .failure(.notAMapping)
        }
    }

    /// Reads the skill of a `trigger` value. Text with no character that is not white space is no skill.
    ///
    /// - Parameter value: The value, or `nil` when the frontmatter does not have the key.
    /// - Returns: The skill, or `nil` for no skill, and `false` when the value is not text and not null.
    private static func skill(of value: YAMLValue?) -> (value: String?, isValid: Bool) {
        switch value {
        case nil, .null?: (nil, true)
        case .string(let text)?: (text.skillName, true)
        case .int?, .double?, .bool?, .array?, .dictionary?: (nil, false)
        }
    }

    /// Reads a `next` value: a YAML boolean, or one of the ``nextWords`` in any case.
    ///
    /// - Parameter value: The value, or `nil` when the frontmatter does not have the key.
    /// - Returns: The value, or ``defaultMovesToNext`` for no value, and `false` when the value is not valid.
    private static func movesToNext(of value: YAMLValue?) -> (value: Bool, isValid: Bool) {
        switch value {
        case nil, .null?:
            (defaultMovesToNext, true)
        case .bool(let movesToNext)?:
            (movesToNext, true)
        case .string(let text)?:
            nextWords[text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
                .map { word in (word, true) } ?? (defaultMovesToNext, false)
        case .int?, .double?, .array?, .dictionary?:
            (defaultMovesToNext, false)
        }
    }
}

// MARK: - Write

extension ColumnTrigger {
    /// Gives a column body with a changed trigger: the frontmatter gets the `trigger` and the `next` keys of the
    /// change, and keeps each other line, and the text after the frontmatter does not change (``FrontmatterLines``).
    ///
    /// A body with no frontmatter gets a frontmatter when the change sets a key. A frontmatter with no key left goes,
    /// unless the text after it opens with a fence line: then an empty frontmatter stays, so that the text stays the
    /// text after the frontmatter.
    ///
    /// - Parameters:
    ///   - body: The column body.
    ///   - skill: The change of the skill. Text with no character that is not white space removes the key, the same
    ///     as `null`.
    ///   - next: The change of `next`. `null` removes the key, so the column gets the default `true`.
    /// - Returns: The new body. With no change, the body as it is.
    static func body(_ body: String, settingSkill skill: FieldUpdate<String>, next: FieldUpdate<Bool>) -> String {
        if case .unchanged = skill, case .unchanged = next {
            return body
        }
        let (frontmatter, content) = FrontmatterDocument.split(text: body)
        let lineEnd = body.hasPrefix(fence + "\r\n") ? "\r\n" : "\n"
        var lines = FrontmatterLines(text: frontmatter ?? "", lineEnd: lineEnd)
        if let value = yamlValue(of: skill) {
            lines.set(triggerKey, to: value)
        }
        if let value = yamlValue(of: next) {
            lines.set(nextKey, to: value)
        }
        let fenceLine = fence + lineEnd
        guard lines.isBlank, FrontmatterDocument.split(text: content).frontmatter == nil else {
            return fenceLine + (lines.isBlank ? "" : lines.text) + fenceLine + content
        }
        return content
    }

    /// Gives the YAML text of the `trigger` line of a skill change.
    ///
    /// - Parameter skill: The change of the skill.
    /// - Returns: `nil` for no change, `.some(nil)` to remove the key, or the YAML text of the skill.
    private static func yamlValue(of skill: FieldUpdate<String>) -> String?? {
        switch skill {
        case .unchanged: nil
        case .cleared: .some(nil)
        case .changed(let text): .some(text.skillName.map(yamlScalar(of:)))
        }
    }

    /// Gives the YAML text of the `next` line of a change.
    ///
    /// - Parameter next: The change of `next`.
    /// - Returns: `nil` for no change, `.some(nil)` to remove the key, or `true` or `false`.
    private static func yamlValue(of next: FieldUpdate<Bool>) -> String?? {
        switch next {
        case .unchanged: nil
        case .cleared: .some(nil)
        case .changed(let movesToNext): .some(String(movesToNext))
        }
    }

    /// Gives the YAML text of a skill: the plain text when YAML reads it back as the same text, else the text in
    /// double quotes. For example, `yes` is in quotes, because YAML reads the plain `yes` as a boolean.
    ///
    /// - Parameter skill: The skill, with no white space at the ends.
    /// - Returns: The YAML scalar text.
    private static func yamlScalar(of skill: String) -> String {
        let plain = try? YAMLValue.parse("\(triggerKey): \(skill)")
        guard plain == .dictionary([triggerKey: .string(skill)]) else {
            return skill.yamlDoubleQuoted
        }
        return skill
    }

    /// Gives the warning of a write that leaves a column body with a problem.
    ///
    /// - Parameter slug: The slug of the column.
    /// - Returns: The warning, or `nil` when the frontmatter has no problem.
    func warning(ofColumn slug: String) -> ResponseWarning? {
        problem.map { problem in
            let message = "The \(problem.subject) in the frontmatter of the body of the column `\(slug)` "
                + "\(problem.fault), so the column uses \(problem.effect). The call wrote the body. To correct it, "
                + "give \(Self.triggerKey) and \(Self.nextKey) to updateColumn, or write the body again."
            return ResponseWarning(message: message, code: Self.warningCode)
        }
    }
}

extension ColumnTrigger.Problem {
    /// The part of the frontmatter that has the problem, for the warning.
    fileprivate var subject: String {
        switch self {
        case .invalidYAML, .notAMapping: "YAML"
        case .invalidValue(let key): "`\(key)` value"
        }
    }

    /// What is wrong, for the warning.
    fileprivate var fault: String {
        switch self {
        case .invalidYAML(let line?): "is not valid at line \(line) of the body"
        case .invalidYAML(nil): "is not valid"
        case .notAMapping: "is not a mapping of keys"
        case .invalidValue(ColumnTrigger.nextKey): "is not true or false"
        case .invalidValue: "is not a skill name"
        }
    }

    /// The value that the column uses in place of the bad value, for the warning.
    fileprivate var effect: String {
        switch self {
        case .invalidYAML, .notAMapping: "no trigger and \(ColumnTrigger.nextKey): true"
        case .invalidValue(ColumnTrigger.nextKey): "\(ColumnTrigger.nextKey): true"
        case .invalidValue: "no trigger"
        }
    }
}

extension String {
    /// The format of the YAML escape of a control character: `\u` and four hexadecimal digits.
    private static let controlEscapeFormat = "\\u%04X"

    /// The escape of each character that YAML double quotes must escape, other than a control character.
    private static let quotedEscapes: [Unicode.Scalar: String] = [
        "\\": "\\\\", "\"": "\\\"", "\n": "\\n", "\r": "\\r", "\t": "\\t",
    ]

    /// The text with no white space or line end at the start and at the end, or `nil` when no character is left.
    fileprivate var skillName: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The text as a YAML double-quoted scalar: a backslash, a double quote, and each control character is an
    /// escape.
    fileprivate var yamlDoubleQuoted: String {
        let escaped = unicodeScalars.map { scalar in
            if let escape = Self.quotedEscapes[scalar] {
                return escape
            }
            guard scalar.properties.generalCategory == .control else {
                return String(scalar)
            }
            return String(format: Self.controlEscapeFormat, scalar.value)
        }
        return "\"" + escaped.joined() + "\""
    }
}
