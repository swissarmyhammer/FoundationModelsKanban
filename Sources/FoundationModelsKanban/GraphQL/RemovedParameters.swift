import FoundationModelsExtras

/// A parameter of the Rust kanban MCP tool that the Swift schema does not have (divergence.md Q12 as P4 changed it,
/// N5).
///
/// The toolkit name rewrite ignores a removed parameter: it takes the parameter out of the document or out of the
/// value of a variable, the call runs, and the response gives a warning in `extensions.warnings` that tells the agent
/// what to use. The rewrite accepts the name in each case and style, so `exclude_done`, `excludeDone`, and
/// `EXCLUDE_DONE` are the same parameter. A name that a field, an argument, or an `input` field of the position has is
/// never a removed parameter. ``GraphQLNameRules/kanban`` gives each case to the rewrite.
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

    /// The parameter as the toolkit name rewrite reads it: the Rust name and the replacement of the warning.
    var toolkitParameter: GraphQLRemovedParameter {
        GraphQLRemovedParameter(name: rawValue, replacement: replacement)
    }
}
