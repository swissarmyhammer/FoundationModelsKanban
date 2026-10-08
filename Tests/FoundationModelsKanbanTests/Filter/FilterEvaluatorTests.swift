import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the evaluation of a parsed filter against the tasks of one board (plan.md §6.3).
///
/// The tag, assignee, ref, AND, OR, NOT, and combined cases are a port of the evaluator tests in the Rust file
/// `swissarmyhammer-filter-expr/src/lib.rs`, without the removed `$project` atom. The marker, virtual tag, keyword,
/// slug-of-name, and "names nothing" cases are a port of the Rust kanban tests `tests/filter_integration.rs` and
/// `src/task/list.rs`. The `%column` atom, the `kanban://` URLs, and the rename redirect are new.
@Suite("Filter evaluator")
struct FilterEvaluatorTests {
    /// The ULID text of the first task of the sample board.
    static let first = ReadinessFixture.first

    /// The ULID text of the second task of the sample board.
    static let second = ReadinessFixture.second

    /// The ULID text of the third task of the sample board.
    static let third = ReadinessFixture.third

    /// The ULID text of the fourth task of the sample board.
    static let fourth = ReadinessFixture.fourth

    /// The ULID text of a task that no board of the tests has.
    static let ghost = ReadinessFixture.ghost

    /// The current key of the sample board.
    static let boardKey = DependencyMarkersTests.boardKey

    /// The key of a different board.
    static let otherBoardKey = DependencyMarkersTests.otherBoardKey

    /// The slug of the actor that has a name of two words.
    static let alice = "alice"

    /// The name of the actor `alice`.
    static let aliceName = "Alice Smith"

    /// The slug of the actor that has a name of one word.
    static let will = "will"

    /// The name that the sample board gives to the column `doing`.
    static let doingName = "In Progress"

    /// The slug of the tag that a rename redirects to the tag `defect`.
    static let oldTag = "old"

    /// The slug of the target of the rename of the tag `old`.
    static let defectTag = "defect"

    /// The real tags of the sample board, other than the renamed tag.
    static let sampleTags = ["bug", "feature", "docs", "done", defectTag]

    /// Gives a URL of a node of a board.
    ///
    /// - Parameters:
    ///   - type: The node type of the node.
    ///   - localID: The local id of the node: a slug or a ULID text.
    ///   - key: The key of the board of the node.
    /// - Returns: The URL, for example `kanban://<board-key>/tag/bug`.
    static func url(ofType type: PatchNodeType, withID localID: String, inBoard key: String = boardKey) -> String {
        "\(NodeURI.scheme)\(key)/\(type.pathSegment)/\(localID)"
    }

    /// Makes the sample board.
    ///
    /// - The first task is in `todo`, has the tag edge `bug`, and is assigned to `alice`.
    /// - The second task is in `doing`, has the marker `#feature`, is assigned to `will`, and depends on the first
    ///   task with an edge.
    /// - The third task is in `done`, has the tag edges `docs` and `done`, and depends on the second task with a
    ///   marker URL in its body.
    /// - The fourth task is in `todo`, has the tag edge `old` (renamed to `defect`), and depends on a task of a
    ///   different board.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a test ULID is not valid.
    static func sampleBoard() throws -> ReadinessFixture {
        var board = ReadinessFixture()
        board.addColumn(withSlug: ReadinessFixture.doing, named: doingName, order: 1)
        board.addActor(withSlug: alice, named: aliceName)
        board.addActor(withSlug: will, named: "Will")
        for slug in sampleTags {
            board.addTag(withSlug: slug)
        }
        board.addTag(withSlug: oldTag, renamedTo: defectTag)
        try board.addTask(withULID: first, taggedWith: ["bug"], assignedTo: [alice])
        try board.addTask(
            withULID: second,
            inColumn: ReadinessFixture.doing,
            assignedTo: [will],
            dependingOn: [first],
            fields: ReadinessFixture.fields(body: "#feature request")
        )
        try board.addTask(
            withULID: third,
            inColumn: ReadinessFixture.done,
            taggedWith: ["docs", "done"],
            fields: ReadinessFixture.fields(body: "after \(DependencyMarkersTests.url(ofTask: second))")
        )
        try board.addTask(
            withULID: fourth,
            taggedWith: [oldTag],
            dependingOnRemote: [try DependencyMarkersTests.uri(ofTask: ghost, inBoard: otherBoardKey)]
        )
        return board
    }

    /// Evaluates a parsed filter against each node of a board, of each node type.
    ///
    /// - Parameters:
    ///   - filter: The parsed filter.
    ///   - board: The board.
    /// - Returns: The local refs of the nodes that match, in slot order.
    static func matchingRefs(of filter: FilterExpr, in board: ReadinessFixture) -> [LocalRef] {
        let evaluator = FilterEvaluator(evaluating: filter, over: board.readiness, inBoard: boardKey)
        return board.graph.allSlots.compactMap { slot in
            evaluator.matches(nodeAt: slot) ? board.graph.node(at: slot)?.ref : nil
        }
    }

    /// Parses a filter and evaluates it against each node of a board, of each node type.
    ///
    /// This is the one place that parses the text of a filter. Each helper that takes the text calls it.
    ///
    /// - Parameters:
    ///   - filter: The text of the filter.
    ///   - board: The board.
    /// - Returns: The local refs of the nodes that match, in slot order.
    /// - Throws: An error when the filter does not parse.
    static func matchingRefs(of filter: String, in board: ReadinessFixture) throws -> [LocalRef] {
        matchingRefs(of: try FilterExpr(parsing: filter), in: board)
    }

    /// Parses a filter and evaluates it against each node of a board, of each node type.
    ///
    /// - Parameters:
    ///   - filter: The text of the filter.
    ///   - board: The board.
    /// - Returns: The text of the local ref of each node that matches, in slot order, for example `column/todo`.
    /// - Throws: An error when the filter does not parse.
    static func nodeMatches(of filter: String, in board: ReadinessFixture) throws -> [String] {
        try matchingRefs(of: filter, in: board).map(\.description)
    }

    /// Gives the ULID text of each task ref in a list of local refs.
    ///
    /// - Parameter refs: The local refs, of each node type.
    /// - Returns: The ULID texts of the task refs, in the order of `refs`.
    static func taskULIDs(in refs: [LocalRef]) -> [String] {
        refs.compactMap { ref in
            guard case .task(let ulid) = ref else {
                return nil
            }
            return ulid.ulidString
        }
    }

    /// Evaluates a parsed filter against each task of a board.
    ///
    /// - Parameters:
    ///   - filter: The parsed filter.
    ///   - board: The board.
    /// - Returns: The ULID texts of the tasks that match, in slot order.
    static func matches(of filter: FilterExpr, in board: ReadinessFixture) -> [String] {
        taskULIDs(in: matchingRefs(of: filter, in: board))
    }

    /// Parses a filter and evaluates it against each task of a board.
    ///
    /// - Parameters:
    ///   - filter: The text of the filter.
    ///   - board: The board.
    /// - Returns: The ULID texts of the tasks that match, in slot order.
    /// - Throws: An error when the filter does not parse.
    static func matches(of filter: String, in board: ReadinessFixture) throws -> [String] {
        taskULIDs(in: try matchingRefs(of: filter, in: board))
    }

    /// Parses a filter and evaluates it against each task of the sample board.
    ///
    /// - Parameter filter: The text of the filter.
    /// - Returns: The ULID texts of the tasks that match, in slot order.
    /// - Throws: An error when the filter does not parse or a test ULID is not valid.
    static func sampleMatches(of filter: String) throws -> [String] {
        try matches(of: filter, in: try sampleBoard())
    }

    // MARK: - Rust evaluator tests

    @Test("A tag atom matches a task with the tag")
    func tagMatch() throws {
        #expect(try Self.sampleMatches(of: "#bug") == [Self.first])
    }

    @Test("A tag atom does not match a task without the tag")
    func tagNoMatch() throws {
        #expect(try !Self.sampleMatches(of: "#feature").contains(Self.first))
    }

    @Test("A tag atom ignores the case of a real tag")
    func tagCaseInsensitive() throws {
        var board = ReadinessFixture()
        board.addTag(withSlug: "ready")
        try board.addTask(withULID: Self.first, taggedWith: ["ready"], dependingOn: [Self.ghost])
        try board.addTask(withULID: Self.second)
        // The first task is blocked, so only its real tag `ready` can match. The second task has the virtual tag.
        #expect(try Self.matches(of: "#READY", in: board) == [Self.first, Self.second])
    }

    @Test("An assignee atom matches a task assigned to the actor")
    func assigneeMatch() throws {
        #expect(try Self.sampleMatches(of: "@will") == [Self.second])
    }

    @Test("A ref atom matches the task and the tasks that depend on it")
    func refMatch() throws {
        #expect(try Self.sampleMatches(of: "^\(Self.first)") == [Self.first, Self.second])
    }

    @Test("AND needs the two sides")
    func and() throws {
        #expect(try Self.sampleMatches(of: "#bug && @alice") == [Self.first])
        #expect(try Self.sampleMatches(of: "#bug && @will").isEmpty)
        #expect(try Self.sampleMatches(of: "#feature && @alice").isEmpty)
    }

    @Test("OR needs one side")
    func or() throws {
        #expect(try Self.sampleMatches(of: "#bug || #feature") == [Self.first, Self.second])
        #expect(try Self.sampleMatches(of: "#nothing-here || #absent").isEmpty)
    }

    @Test("NOT inverts the match")
    func not() throws {
        #expect(try Self.sampleMatches(of: "!#done") == [Self.first, Self.second, Self.fourth])
    }

    @Test("A combined filter with groups, AND, and NOT")
    func complexExpression() throws {
        #expect(try Self.sampleMatches(of: "(#bug || #feature) && @will && !#done") == [Self.second])
        #expect(try Self.sampleMatches(of: "(#bug || #feature) && @alice && !#done") == [Self.first])
    }

    // MARK: - Rust kanban tests

    @Test("A body marker gives a tag that a tag atom matches")
    func markerTag() throws {
        #expect(try Self.sampleMatches(of: "#feature") == [Self.second])
    }

    @Test("Two atoms next to each other are an AND")
    func implicitAnd() throws {
        #expect(try Self.sampleMatches(of: "#bug @alice") == [Self.first])
        #expect(try Self.sampleMatches(of: "#bug @will").isEmpty)
    }

    @Test("The virtual tags READY, BLOCKED, and BLOCKING")
    func virtualTags() throws {
        #expect(try Self.sampleMatches(of: "#READY") == [Self.first])
        #expect(try Self.sampleMatches(of: "#BLOCKED") == [Self.second, Self.third, Self.fourth])
        #expect(try Self.sampleMatches(of: "#BLOCKING") == [Self.first, Self.second])
    }

    @Test("A virtual tag ignores case")
    func virtualTagCaseInsensitive() throws {
        #expect(try Self.sampleMatches(of: "#ready") == [Self.first])
        #expect(try Self.sampleMatches(of: "#Blocking") == [Self.first, Self.second])
    }

    @Test("A virtual tag together with a real tag")
    func virtualTagWithRealTag() throws {
        #expect(try Self.sampleMatches(of: "#READY && #bug") == [Self.first])
        #expect(try Self.sampleMatches(of: "#READY && #feature").isEmpty)
    }

    @Test("The virtual tag CONFLICT")
    func conflictTag() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(hasConflict: true))
        try board.addTask(withULID: Self.second)
        #expect(try Self.matches(of: "#CONFLICT", in: board) == [Self.first])
    }

    @Test("The virtual tag DONE matches a live task in the terminal column, and NOT DONE matches the others")
    func doneTag() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: Self.first, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: Self.second)
        let tombstone = ReadinessFixture.fields(isDeleted: true)
        try board.addTask(withULID: Self.third, inColumn: ReadinessFixture.done, fields: tombstone)
        #expect(try Self.matches(of: "#DONE", in: board) == [Self.first])
        #expect(try Self.matches(of: "!#DONE", in: board) == [Self.second, Self.third])
    }

    @Test("The keyword operators in lowercase")
    func lowercaseKeywords() throws {
        #expect(try Self.sampleMatches(of: "not #done and @alice or #docs") == [Self.first, Self.third])
    }

    @Test("The keyword operators in uppercase")
    func uppercaseKeywords() throws {
        #expect(try Self.sampleMatches(of: "NOT #done AND @will") == [Self.second])
    }

    @Test("A tag that names nothing matches nothing")
    func unknownTag() throws {
        #expect(try Self.sampleMatches(of: "#nonexistent-tag").isEmpty)
    }

    @Test("A tag marker stops at a character that a slug does not keep")
    func markerWithDot() throws {
        var board = ReadinessFixture()
        board.addTag(withSlug: "v2")
        board.addTag(withSlug: "bug-fix")
        try board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(body: "#v2.0 release"))
        try board.addTask(withULID: Self.second, fields: ReadinessFixture.fields(body: "#bug-fix found"))
        try board.addTask(withULID: Self.third)
        #expect(try Self.matches(of: "#v2", in: board) == [Self.first])
        #expect(try Self.matches(of: "#bug-fix", in: board) == [Self.second])
    }

    @Test("An assignee atom matches the slug of the actor name")
    func assigneeSlugOfName() throws {
        #expect(try Self.sampleMatches(of: "@alice-smith") == [Self.first])
        #expect(try Self.sampleMatches(of: "@Alice_Smith") == [Self.first])
    }

    @Test("An assignee atom ignores case")
    func assigneeCaseInsensitive() throws {
        #expect(try Self.sampleMatches(of: "@ALICE") == [Self.first])
    }

    @Test("An assignee atom that names nothing matches nothing")
    func unknownAssignee() throws {
        #expect(try Self.sampleMatches(of: "@nobody").isEmpty)
    }

    @Test("An assignee atom does not match a tombstoned actor")
    func tombstonedAssignee() throws {
        var board = ReadinessFixture()
        board.addActor(withSlug: Self.will, isDeleted: true)
        try board.addTask(withULID: Self.first, assignedTo: [Self.will])
        #expect(try Self.matches(of: "@will", in: board).isEmpty)
    }

    // MARK: - Tags

    @Test("A tag atom follows the rename redirect from an edge")
    func renamedTagEdge() throws {
        #expect(try Self.sampleMatches(of: "#defect") == [Self.fourth])
        #expect(try Self.sampleMatches(of: "#old") == [Self.fourth])
    }

    @Test("A tag atom matches a marker of a renamed tag")
    func renamedTagMarker() throws {
        var board = ReadinessFixture()
        board.addTag(withSlug: Self.defectTag)
        board.addTag(withSlug: Self.oldTag, renamedTo: Self.defectTag)
        try board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(body: "#old"))
        #expect(try Self.matches(of: "#defect", in: board) == [Self.first])
    }

    // MARK: - Columns

    @Test("A column atom matches the tasks in the column")
    func columnMatch() throws {
        #expect(try Self.sampleMatches(of: "%todo") == [Self.first, Self.fourth])
        #expect(try Self.sampleMatches(of: "%done") == [Self.third])
    }

    @Test("A column atom matches the slug of the column name")
    func columnSlugOfName() throws {
        #expect(try Self.sampleMatches(of: "%in-progress") == [Self.second])
        #expect(try Self.sampleMatches(of: "%In_Progress") == [Self.second])
    }

    @Test("A column atom ignores case")
    func columnCaseInsensitive() throws {
        #expect(try Self.sampleMatches(of: "%DOING") == [Self.second])
    }

    @Test("A task with no column shows in the first column")
    func taskWithNoColumn() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: Self.first, inColumn: nil)
        #expect(try Self.matches(of: "%todo", in: board) == [Self.first])
    }

    @Test("A column atom that names nothing matches nothing")
    func unknownColumn() throws {
        #expect(try Self.sampleMatches(of: "%nowhere").isEmpty)
    }

    @Test("A column atom with a column and a tag")
    func columnWithReady() throws {
        #expect(try Self.sampleMatches(of: "%doing || (%todo && #READY)") == [Self.first, Self.second])
    }

    // MARK: - Refs

    @Test("A ref atom matches a dependency from a body marker")
    func refMarker() throws {
        #expect(try Self.sampleMatches(of: "^\(Self.second)") == [Self.second, Self.third])
    }

    @Test("A ref atom accepts the short id in each case")
    func refShortID() throws {
        let shortID = ShortID(ofULIDString: Self.first).value
        #expect(try Self.sampleMatches(of: "^\(shortID)") == [Self.first, Self.second])
        #expect(try Self.sampleMatches(of: "^\(shortID.uppercased())") == [Self.first, Self.second])
    }

    @Test("A ref atom accepts the full ULID in lowercase")
    func refLowercaseULID() throws {
        #expect(try Self.sampleMatches(of: "^\(Self.first.lowercased())") == [Self.first, Self.second])
    }

    @Test("A ULID prefix resolves among the task and its dependencies, as in Rust")
    func refPrefix() throws {
        // `01KT6R` starts the first and the second ULID. For the second task, its two candidates make the prefix
        // ambiguous, so it does not match. For the third task, the one candidate is the second task.
        #expect(try Self.sampleMatches(of: "^01KT6R") == [Self.first, Self.third])
        #expect(try Self.sampleMatches(of: "^01KT6R6") == [Self.first, Self.second])
    }

    @Test("A ref atom that names nothing matches nothing")
    func unknownRef() throws {
        #expect(try Self.sampleMatches(of: "^\(Self.ghost)").isEmpty)
    }

    // MARK: - URLs

    /// Each short form of the sample board, with the URL of the same node.
    static let urlForms: [(String, String)] = [
        ("#bug", url(ofType: .tag, withID: "bug")),
        ("@alice", url(ofType: .actor, withID: alice)),
        ("%doing", url(ofType: .column, withID: ReadinessFixture.doing)),
        ("^\(first)", url(ofType: .task, withID: first)),
    ]

    @Test("A URL after its sigil matches the same tasks as the short form", arguments: urlForms)
    func urlAfterSigil(shortForm: String, url: String) throws {
        let expected = try Self.sampleMatches(of: shortForm)
        let sigil = try #require(shortForm.first)
        #expect(!expected.isEmpty)
        #expect(try Self.sampleMatches(of: "\(sigil)\(url)") == expected)
    }

    @Test("A bare URL matches the same tasks as the short form", arguments: urlForms)
    func bareURL(shortForm: String, url: String) throws {
        let expected = try Self.sampleMatches(of: shortForm)
        #expect(!expected.isEmpty)
        #expect(try Self.sampleMatches(of: url) == expected)
    }

    @Test(
        "A tag, actor, or column URL of a different board matches nothing",
        arguments: [
            url(ofType: .tag, withID: "bug", inBoard: otherBoardKey),
            url(ofType: .actor, withID: alice, inBoard: otherBoardKey),
            url(ofType: .column, withID: ReadinessFixture.doing, inBoard: otherBoardKey),
        ]
    )
    func otherBoardURL(url: String) throws {
        #expect(try Self.sampleMatches(of: url).isEmpty)
    }

    @Test("A task URL of a different board matches the tasks that depend on that task")
    func otherBoardTaskURL() throws {
        let url = Self.url(ofType: .task, withID: Self.ghost, inBoard: Self.otherBoardKey)
        #expect(try Self.sampleMatches(of: "^\(url)") == [Self.fourth])
        #expect(try Self.sampleMatches(of: url) == [Self.fourth])
    }

    /// Each URL after a sigil of a different kind, with the atom that has the correct sigil.
    static let wrongTypeURLs: [(String, String)] = [
        ("#\(url(ofType: .task, withID: first))", "^\(url(ofType: .task, withID: first))"),
        ("~\(url(ofType: .tag, withID: "bug"))", "#\(url(ofType: .tag, withID: "bug"))"),
        ("%\(url(ofType: .actor, withID: alice))", "@\(url(ofType: .actor, withID: alice))"),
        ("@\(url(ofType: .column, withID: "doing"))", "%\(url(ofType: .column, withID: "doing"))"),
    ]

    @Test("A URL of the wrong type gives INVALID_FILTER with the correct form", arguments: wrongTypeURLs)
    func wrongTypeURL(filter: String, correctForm: String) throws {
        let error = try #require(throws: KanbanError.self) {
            try FilterExpr(parsing: filter)
        }
        #expect(error.code == "INVALID_FILTER")
        #expect(error.message.contains(correctForm))
    }

    @Test("An atom whose URL has a different node type matches nothing")
    func mismatchedAtomMatchesNothing() throws {
        let uri = try DependencyMarkersTests.uri(ofTask: Self.first)
        #expect(Self.matches(of: .atom(.tag, .uri(uri)), in: try Self.sampleBoard()).isEmpty)
    }

    // MARK: - Nodes of each type

    /// Gives the text of the local ref of a node that a slug finds.
    ///
    /// - Parameters:
    ///   - slug: The slug of the node.
    ///   - makeRef: The constructor of the local ref, for example `LocalRef.column(slug:)`.
    /// - Returns: The text, for example `column/todo`.
    static func refText(ofSlug slug: String, as makeRef: (String) -> LocalRef) -> String {
        makeRef(slug).description
    }

    /// Gives the text of the local ref of each node in a list of slugs.
    ///
    /// - Parameters:
    ///   - slugs: The slugs of the nodes.
    ///   - makeRef: The constructor of the local ref, for example `LocalRef.actor(slug:)`.
    /// - Returns: The texts, in the order of `slugs`.
    static func refTexts(ofSlugs slugs: [String], as makeRef: (String) -> LocalRef) -> [String] {
        slugs.map { slug in refText(ofSlug: slug, as: makeRef) }
    }

    /// The text of the local ref of each column of the sample board, in slot order.
    static let sampleColumns = refTexts(ofSlugs: ReadinessFixture.defaultColumns, as: LocalRef.column(slug:))

    /// Gives the text of the local ref of a task.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The text, for example `task/01KT6R…`.
    /// - Throws: An error when the text is not a ULID.
    static func taskRef(_ text: String) throws -> String {
        LocalRef.task(try DependencyMarkersTests.ulid(of: text)).description
    }

    /// Makes a board with one task and one comment on the task.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a test ULID is not valid.
    static func commentBoard() throws -> ReadinessFixture {
        var board = ReadinessFixture()
        board.addActor(withSlug: ReadinessFixture.author)
        try board.addTask(withULID: first)
        try board.addComment(withULID: ReadinessFixture.firstComment, onTask: first)
        return board
    }

    @Test("A node type atom matches each node of the type, in any case", arguments: ["~column", "~COLUMN", "~Column"])
    func nodeTypeAtomMatchesNodesOfType(filter: String) throws {
        #expect(try Self.nodeMatches(of: filter, in: try Self.sampleBoard()) == Self.sampleColumns)
    }

    @Test("~task matches the tasks and no other node, and ~actor the actors")
    func nodeTypeAtomOfTasksAndActors() throws {
        let board = try Self.sampleBoard()
        let tasks = try [Self.first, Self.second, Self.third, Self.fourth].map(Self.taskRef)
        #expect(try Self.nodeMatches(of: "~task", in: board) == tasks)
        let actors = Self.refTexts(ofSlugs: [Self.alice, Self.will], as: LocalRef.actor(slug:))
        #expect(try Self.nodeMatches(of: "~actor", in: board) == actors)
    }

    @Test("A node type atom that names no node type matches nothing")
    func unknownNodeTypeMatchesNothing() throws {
        #expect(try Self.nodeMatches(of: "~project", in: try Self.sampleBoard()).isEmpty)
    }

    @Test("A task atom does not match a node of a different type, so its NOT matches each such node")
    func taskAtomOnOtherNode() throws {
        let board = try Self.sampleBoard()
        #expect(try Self.nodeMatches(of: "#bug", in: board) == [try Self.taskRef(Self.first)])
        #expect(try Self.nodeMatches(of: "%todo || @alice || #READY", in: board) == [
            try Self.taskRef(Self.first), try Self.taskRef(Self.fourth),
        ])
        #expect(try Self.nodeMatches(of: "!#bug && ~column", in: board) == Self.sampleColumns)
    }

    @Test("A ref atom matches a node of a different type by its slug or its URL, and only that node", arguments: [
        "^doing", "^\(url(ofType: .column, withID: ReadinessFixture.doing))",
    ])
    func refAtomMatchesColumn(filter: String) throws {
        let doing = Self.refText(ofSlug: ReadinessFixture.doing, as: LocalRef.column(slug:))
        #expect(try Self.nodeMatches(of: filter, in: try Self.sampleBoard()) == [doing])
    }

    @Test("A ref atom of a comment matches the comment, and a ref atom of the task does not match its comment")
    func refAtomOfComment() throws {
        let board = try Self.commentBoard()
        let comment = LocalRef.comment(try DependencyMarkersTests.ulid(of: ReadinessFixture.firstComment))
        let commentShortID = ShortID(ofULIDString: ReadinessFixture.firstComment).value
        #expect(try Self.nodeMatches(of: "^\(commentShortID)", in: board) == [comment.description])
        #expect(try Self.nodeMatches(of: "^\(Self.first)", in: board) == [try Self.taskRef(Self.first)])
    }

    // MARK: - Names a virtual tag

    /// Each filter of the "names DONE" test, with `true` when it has a `#DONE` atom, a column atom, a ref atom, or a
    /// `~task` atom at some depth.
    static let doneNamings: [(String, Bool)] = [
        ("#DONE", true),
        ("@alice && !#done", true),
        (url(ofType: .tag, withID: "DONE"), true),
        ("%doing", true),
        ("#bug && !%done", true),
        ("(@alice || %todo) #bug", true),
        (url(ofType: .column, withID: "doing"), true),
        ("^\(first) || #READY", true),
        ("#bug && ~Task", true),
        ("#bug", false),
        ("#DELETED", false),
        ("@done", false),
        ("~column", false),
        (url(ofType: .tag, withID: "bug"), false),
    ]

    @Test(
        "A filter names the virtual tag DONE with a #DONE, column, ref, or ~task atom, at any depth and in any case",
        arguments: doneNamings
    )
    func namesDone(filter: String, isNamed: Bool) throws {
        #expect(try FilterExpr(parsing: filter).names(.done) == isNamed)
    }

    /// Each filter of the "names DELETED" test, with `true` when it has a `#DELETED` atom, a ref atom, or a `~task`
    /// atom at some depth.
    static let deletedNamings: [(String, Bool)] = [
        ("#DELETED", true),
        ("!#deleted", true),
        ("#bug || (@alice && #Deleted)", true),
        (url(ofType: .tag, withID: "DELETED"), true),
        ("^\(first)", true),
        ("!~TASK", true),
        ("#bug", false),
        ("#READY", false),
        ("%deleted", false),
        ("@deleted", false),
        ("~comment", false),
    ]

    @Test(
        "A filter names the virtual tag DELETED with a #DELETED, ref, or ~task atom, at any depth and in any case",
        arguments: deletedNamings
    )
    func namesDeleted(filter: String, isNamed: Bool) throws {
        #expect(try FilterExpr(parsing: filter).names(.deleted) == isNamed)
    }
}
