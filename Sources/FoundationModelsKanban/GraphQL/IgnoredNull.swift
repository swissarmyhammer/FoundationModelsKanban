import FoundationModelsExtras

/// The rule for `null` on a required text field of an update input: the task `title`, and the `name` of a column, an
/// actor, or a tag (divergence.md Q17).
///
/// Rust ignores `null` on these fields, and so does this package: `null` means "no change". The call works, the field
/// keeps its value, and a warning tells the agent that the call ignored the `null`. A `null` on an optional field, for
/// example a `body` or a `color`, still clears the field.
enum IgnoredNull {
    /// The code of the warning that tells the agent that the call ignored `null` on a required text field.
    static let warningCode = "NULL_IGNORED"

    /// Gives the warning of one required text field of an update input.
    ///
    /// - Parameters:
    ///   - update: The update of the field, as the input gives it.
    ///   - field: The name of the field, for example `title`.
    ///   - mutation: The name of the public mutation, for example `updateTask`.
    /// - Returns: One warning when the input gives `null`, else no warning.
    static func warnings(
        of update: FieldUpdate<String>,
        forField field: String,
        of mutation: String
    ) -> [ResponseWarning] {
        guard update.isCleared else {
            return []
        }
        let message = "`\(field)` is a required field of `\(mutation)`, so the call ignored `null` and the field "
            + "keeps its value. To change the field, give a text value."
        return [ResponseWarning(message: message, code: warningCode)]
    }
}

extension FieldUpdate {
    /// The update to write for a required text field (``IgnoredNull``): `null` gives no change, and a missing field
    /// or a value stays as it is.
    var ignoringNull: FieldUpdate {
        isCleared ? .unchanged : self
    }
}

extension KanbanContext {
    /// Adds the warning of one required text field of an update input to the warnings of the run (``IgnoredNull``).
    /// A field that is not `null` adds no warning.
    ///
    /// - Parameters:
    ///   - update: The update of the field, as the input gives it.
    ///   - field: The name of the field, for example `title`.
    ///   - mutation: The name of the public mutation, for example `updateTask`.
    func warnIfNull(_ update: FieldUpdate<String>, forField field: String, of mutation: String) async {
        await warnings.add(contentsOf: IgnoredNull.warnings(of: update, forField: field, of: mutation))
    }
}
