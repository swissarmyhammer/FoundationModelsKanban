import Testing

@testable import FoundationModelsKanban

/// Tests the read and the write of the trigger of a column in the YAML frontmatter of its body (divergence.md §22,
/// TestudoApp KANBAN-2).
@Suite("Column trigger frontmatter")
struct ColumnTriggerTests {
    /// The skill of the trigger in the tests.
    static let skill = "do"

    /// The Markdown text after the frontmatter in the tests.
    static let text = "Tasks that wait for a check.\n"

    /// A frontmatter key that is not a trigger key, so that the write must keep it.
    private static let ownerLine = "owner: qa\n"

    /// A frontmatter with YAML that does not parse: a second colon of a plain value, on line 2 of the body.
    static let badYAMLBody = "---\ntrigger: do: now\n---\n" + text

    /// Each body with the trigger that it gives: the skill, the `next` value, and the problem.
    static let readCases: [(String, ColumnTrigger)] = [
        ("", ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        (text, ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        ("---\n---\n" + text, ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        ("---\ntrigger: do\n---\n" + text, ColumnTrigger(skill: skill, movesToNext: true, problem: nil)),
        ("---\ntrigger: do\nnext: false\n---\n", ColumnTrigger(skill: skill, movesToNext: false, problem: nil)),
        (
            "---\r\ntrigger: do\r\nnext: false\r\n---\r\n",
            ColumnTrigger(skill: skill, movesToNext: false, problem: nil)
        ),
        ("---\ntrigger: \"  do \"\n---\n", ColumnTrigger(skill: skill, movesToNext: true, problem: nil)),
        ("---\ntrigger: ''\n---\n", ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        ("---\ntrigger: null\nnext: null\n---\n", ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        ("---\nnext: \"No\"\n---\n", ColumnTrigger(skill: nil, movesToNext: false, problem: nil)),
        ("---\nnext: \"TRUE\"\n---\n", ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        // The text after an opening fence with no closing fence is the body, so it is not a frontmatter.
        ("---\ntrigger: do\n", ColumnTrigger(skill: nil, movesToNext: true, problem: nil)),
        (badYAMLBody, ColumnTrigger(skill: nil, movesToNext: true, problem: .invalidYAML(line: 2))),
        ("---\n- do\n---\n", ColumnTrigger(skill: nil, movesToNext: true, problem: .notAMapping)),
        (
            "---\ntrigger: [do]\nnext: false\n---\n",
            ColumnTrigger(skill: nil, movesToNext: false, problem: .invalidValue(key: ColumnTrigger.triggerKey))
        ),
        (
            "---\ntrigger: do\nnext: later\n---\n",
            ColumnTrigger(skill: skill, movesToNext: true, problem: .invalidValue(key: ColumnTrigger.nextKey))
        ),
    ]

    /// Each body, with the trigger change of a write and the body after the write.
    static let editCases: [(String, FieldUpdate<String>, FieldUpdate<Bool>, String)] = [
        ("", .changed(skill), .unchanged, "---\ntrigger: do\n---\n"),
        (text, .changed(skill), .unchanged, "---\ntrigger: do\n---\n" + text),
        (text, .changed(skill), .changed(false), "---\ntrigger: do\nnext: false\n---\n" + text),
        // A write keeps each other key and the text after the frontmatter, and changes the key in its place.
        (
            "---\ntrigger: old\n" + ownerLine + "---\n" + text, .changed(skill), .unchanged,
            "---\ntrigger: do\n" + ownerLine + "---\n" + text
        ),
        (
            "---\n" + ownerLine + "---\n" + text, .unchanged, .changed(true),
            "---\n" + ownerLine + "next: true\n---\n" + text
        ),
        // A value on the lines after the key goes with the key.
        (
            "---\ntrigger: >\n  old\n" + ownerLine + "---\n", .changed(skill), .unchanged,
            "---\ntrigger: do\n" + ownerLine + "---\n"
        ),
        // A second line of the same key goes, so the frontmatter has no duplicate key.
        ("---\ntrigger: a\ntrigger: b\n---\n", .changed(skill), .unchanged, "---\ntrigger: do\n---\n"),
        // A new key line gets the line end of the frontmatter.
        (
            "---\r\nowner: qa\r\n---\r\n", .changed(skill), .unchanged,
            "---\r\nowner: qa\r\ntrigger: do\r\n---\r\n"
        ),
        // A value that YAML reads as a different value is in quotes.
        ("", .changed("yes"), .unchanged, "---\ntrigger: \"yes\"\n---\n"),
        ("", .changed("a: b"), .unchanged, "---\ntrigger: \"a: b\"\n---\n"),
        ("", .changed(" do "), .unchanged, "---\ntrigger: do\n---\n"),
        // A clear removes the key, and a frontmatter with no key left goes.
        (
            "---\ntrigger: do\n" + ownerLine + "---\n" + text, .cleared, .unchanged,
            "---\n" + ownerLine + "---\n" + text
        ),
        ("---\ntrigger: do\nnext: false\n---\n" + text, .cleared, .cleared, text),
        ("---\ntrigger: do\n---\n" + text, .changed(""), .unchanged, text),
        (text, .cleared, .unchanged, text),
        // The text after the frontmatter that opens with a fence keeps an empty frontmatter in front of it.
        ("---\ntrigger: do\n---\n---\nx\n---\n", .cleared, .unchanged, "---\n---\n---\nx\n---\n"),
        // A frontmatter with bad YAML still gets the line of the key.
        (badYAMLBody, .changed(skill), .unchanged, "---\ntrigger: do\n---\n" + text),
    ]

    @Test("A column body gives the trigger skill and the next value of its frontmatter", arguments: readCases)
    func bodyGivesTrigger(body: String, expected: ColumnTrigger) {
        #expect(ColumnTrigger(body: body) == expected)
    }

    @Test(
        "A trigger write sets or removes the trigger and next keys, and keeps the other keys and the text",
        arguments: editCases
    )
    func writeSetsTriggerKeys(body: String, skill: FieldUpdate<String>, next: FieldUpdate<Bool>, expected: String) {
        #expect(ColumnTrigger.body(body, settingSkill: skill, next: next) == expected)
    }

    @Test("A skill that a write puts in quotes reads back as the same skill", arguments: ["yes", "a: b", "#x", "1"])
    func quotedSkillReadsBack(skill: String) {
        let body = ColumnTrigger.body("", settingSkill: .changed(skill), next: .unchanged)
        #expect(ColumnTrigger(body: body).skill == skill)
    }
}
