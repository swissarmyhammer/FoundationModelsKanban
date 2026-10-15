/// A parameter of the Rust kanban MCP tool that the Swift schema does not have (divergence.md Q12 as P4 changed it,
/// N5).
///
/// The name rewrite ignores a removed parameter: it takes the parameter out of the document or out of the value of a
/// variable, the call runs, and the response gives a warning in `extensions.warnings` that tells the agent what to
/// use. The rewrite accepts the name in each case and style, so `exclude_done`, `excludeDone`, and `EXCLUDE_DONE` are
/// the same parameter. A name that a field, an argument, or an `input` field of the position has is never a removed
/// parameter.
enum RemovedParameter: String, CaseIterable, Sendable {
    /// `project`: the board has no projects.
    case project

    /// `due`: a task has no due date.
    case due

    /// `scheduled`: a task has no scheduled date.
    case scheduled

    /// `exclude_done`: a task list takes only the filter.
    case excludeDone = "exclude_done"

    /// `page`: a task list pages with a cursor.
    case page

    /// `detail`: the selection set chooses the fields.
    case detail

    /// `include_counts`: the counts are fields of the result.
    case includeCounts = "include_counts"

    /// `attachments`: a task has no attachments.
    case attachments

    /// The code of the warning of a removed parameter.
    static let warningCode = "REMOVED_PARAMETER"

    /// Gives the removed parameter that a name of the agent names.
    ///
    /// - Parameter name: The name as the agent wrote it, in any case and style.
    /// - Returns: The removed parameter, or `nil` when the name is not a removed parameter.
    init?(matching name: String) {
        guard let parameter = Self.allCases.first(where: { NameMatcher.hasSameWords(name, as: $0.rawValue) }) else {
            return nil
        }
        self = parameter
    }

    /// What the agent can do in place of the parameter, as the end of the warning sentence.
    private var replacement: String {
        switch self {
        case .project: "use tags."
        case .due, .scheduled: "with no replacement: write the date in the body."
        case .excludeDone: "use the filter `!#DONE`."
        case .page: "use `first` and `after` (cursor paging)."
        case .detail: "choose the fields in the selection set."
        case .includeCounts: "select `summary` (or `totalCount`)."
        case .attachments: "with no replacement."
        }
    }

    /// Gives the warning of the parameter for the response.
    ///
    /// - Parameter name: The name as the agent wrote it. The warning quotes this name.
    /// - Returns: The warning, for example "`due` is removed, with no replacement: write the date in the body. The
    ///   call ignored it."
    func warning(writtenAs name: String) -> ResponseWarning {
        ResponseWarning(message: "`\(name)` is removed, \(replacement) The call ignored it.", code: Self.warningCode)
    }
}
