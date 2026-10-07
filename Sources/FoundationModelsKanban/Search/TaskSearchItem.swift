import FoundationModelsMetadataRegistry

/// One task as an item of the search catalog of a board (plan.md §6.4).
///
/// The `id` is the full URI of the task, so that a match gives the task again directly. The rendered block is the
/// search surface: the title, the tag names, and the body, each on its own line.
struct TaskSearchItem: SearchableMetadata {
    /// The text between two parts of the rendered block.
    private static let partSeparator = "\n"

    /// The text between two tag names in the rendered block.
    private static let tagSeparator = " "

    /// The full URI of the task: the join key of the catalog.
    let id: String

    /// The title of the task.
    private let title: String

    /// The names of the live tags of the task: the edges and the markers (plan.md §6.1).
    private let tagNames: [String]

    /// The Markdown body of the task.
    private let body: String

    /// Makes the catalog item of a task.
    ///
    /// - Parameter task: A live task of a board.
    init(of task: TaskObject) {
        id = task.id.text
        title = task.title
        tagNames = task.tags.map(\.name)
        body = task.body
    }

    /// Renders the task to the text of its search surface: the title, the tag names, and the body.
    ///
    /// - Returns: The rendered block.
    func renderBlock() -> String {
        [title, tagNames.joined(separator: Self.tagSeparator), body].joined(separator: Self.partSeparator)
    }
}
