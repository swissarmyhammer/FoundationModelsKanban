import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

extension Design {
    /// Tests a `union` merge of two branches of one board (plan.md §5.2, §5.3, §5.5, §6.2, §11).
    ///
    /// Each test runs the base setup of ``ChangeBuilderTests`` and its own setup on the main branch. Then it copies
    /// the `.kanban/` directory to a second repo: the other branch. Each branch runs its own calls. The merge is the
    /// git `union` driver on each log file: the merged log holds the lines of one branch, then each line of the
    /// other branch that the first branch does not hold. A new commit session loads the merged board, and the test
    /// queries it. Each query must give no error, because replay never refuses a log (plan.md §3.3, rule 7).
    @Suite("Design: union merge of two branches")
    struct MergeTests {
        /// One branch of the board: a repo, and the commit session of its board.
        struct Branch {
            /// The temporary repo directory. The value holds it, so that the repo stays on disk while the test runs.
            let directory: TemporaryDirectory

            /// The commit session of the board of the branch.
            var session: CommitSession

            /// The event log of the board of the branch.
            var log: EventLog {
                session.live.log
            }
        }

        /// The time step of the ids of the calls on the other branch. Each of these ids is after each id of the main
        /// branch, so the two branches never make the same id.
        static let otherBranchStep = CommitTests.callStep + 1

        /// The time step of the ids of the calls after the merge. Each of these ids is after each id of the two
        /// branches.
        static let mergedStep = otherBranchStep + 1

        /// The index of the body line that the main branch changes.
        static let mainLineIndex = 1

        /// The index of the body line that the other branch changes. It is far from ``mainLineIndex``, so that the
        /// two hunks have no line in common.
        static let otherLineIndex = UndoTests.bodyLines.count - 2

        /// The selection of the tags of a task.
        static let tagsSelection = "{ tags { id } }"

        /// The selection of the body of a node.
        static let bodySelection = "{ body }"

        /// The name of the virtual tag of a task with a conflict block.
        static let conflictTag = VirtualTag.conflict.rawValue

        // MARK: - Branches

        /// Makes the main branch: the fixture repo after the base setup of ``ChangeBuilderTests``.
        ///
        /// - Returns: The branch.
        static func mainBranch() async throws -> Branch {
            let directory = try TemporaryDirectory()
            let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
            return Branch(directory: directory, session: session)
        }

        /// Copies the `.kanban/` directory of a branch to a new temporary repo.
        ///
        /// - Parameter source: The branch to copy.
        /// - Returns: The new repo directory, and the event log of its board.
        static func copyBoard(of source: Branch) throws -> (directory: TemporaryDirectory, log: EventLog) {
            let directory = try TemporaryDirectory()
            let log = EventLog(repositoryAt: directory.url)
            try FileManager.default.copyItem(at: source.log.directory, to: log.directory)
            return (directory, log)
        }

        /// Loads the board of a repo in a new commit session.
        ///
        /// - Parameters:
        ///   - directory: The repo directory.
        ///   - log: The event log of the board of the repo.
        ///   - step: The time step of the ids of the calls of the session.
        /// - Returns: The branch.
        static func loadBranch(
            in directory: TemporaryDirectory,
            of log: EventLog,
            mintingAtStep step: Int
        ) async throws -> Branch {
            let ids = FixedULIDSource(at: ReplayTests.date(atStep: step))
            return Branch(directory: directory, session: try await CommitTests.makeSession(of: log, mintingFrom: ids))
        }

        /// Makes a new branch from a copy of the board of a branch.
        ///
        /// - Parameters:
        ///   - source: The branch to copy.
        ///   - step: The time step of the ids of the calls of the new branch.
        /// - Returns: The new branch.
        static func branch(copying source: Branch, mintingAtStep step: Int) async throws -> Branch {
            let copy = try copyBoard(of: source)
            return try await loadBranch(in: copy.directory, of: copy.log, mintingAtStep: step)
        }

        /// Merges two branches with the `union` driver, in a new repo: a copy of the base branch, plus each line of
        /// the incoming branch that the base branch does not hold.
        ///
        /// - Parameters:
        ///   - incoming: The branch whose new lines the merge appends.
        ///   - base: The branch that the merge copies.
        /// - Returns: The merged branch. Its calls make ids at ``mergedStep``.
        static func merge(_ incoming: Branch, into base: Branch) async throws -> Branch {
            let copy = try copyBoard(of: base)
            for ref in try incoming.log.nodeFileSignatures().keys {
                let known = Set(try copy.log.readLog(of: ref).events)
                let missing = try incoming.log.readLog(of: ref).events.filter { event in !known.contains(event) }
                if !missing.isEmpty {
                    try copy.log.append(contentsOf: missing, toLogOf: ref)
                }
            }
            return try await loadBranch(in: copy.directory, of: copy.log, mintingAtStep: mergedStep)
        }

        /// Runs the setup fields on the main branch, makes the other branch, and runs the fields of each branch. Each
        /// field runs in its own call, and must give no error.
        ///
        /// - Parameters:
        ///   - setup: The fields that run on the main branch before the other branch is made.
        ///   - mainFields: The fields of the main branch after the split.
        ///   - otherFields: The fields of the other branch.
        /// - Returns: The two branches.
        static func branches(
            after setup: [String] = [],
            runningOnMain mainFields: [String],
            runningOnOther otherFields: [String]
        ) async throws -> (main: Branch, other: Branch) {
            var main = try await mainBranch()
            try await HistoryTests.run(eachOf: setup, in: &main.session)
            var other = try await branch(copying: main, mintingAtStep: otherBranchStep)
            try await HistoryTests.run(eachOf: mainFields, in: &main.session)
            try await HistoryTests.run(eachOf: otherFields, in: &other.session)
            return (main, other)
        }

        /// Runs ``branches(after:runningOnMain:runningOnOther:)``, and merges the other branch into the main branch.
        ///
        /// - Parameters:
        ///   - setup: The fields that run on the main branch before the other branch is made.
        ///   - mainFields: The fields of the main branch after the split.
        ///   - otherFields: The fields of the other branch.
        /// - Returns: The merged board.
        static func mergedBoard(
            after setup: [String] = [],
            runningOnMain mainFields: [String],
            runningOnOther otherFields: [String]
        ) async throws -> Branch {
            let branches = try await branches(after: setup, runningOnMain: mainFields, runningOnOther: otherFields)
            return try await merge(branches.other, into: branches.main)
        }

        // MARK: - Fields

        /// Makes a `tagTask` field that adds one tag to a task.
        ///
        /// - Parameters:
        ///   - tag: The tag slug.
        ///   - task: The ULID of the task.
        /// - Returns: The field.
        static func tagField(naming tag: String, of task: ULID) -> String {
            ChangeBuilderTests.tagField(of: ChangeBuilderTests.CaseRefs(task: task, comment: ""), naming: tag)
        }

        /// Gives the lines of ``UndoTests/bodyLines`` with one line changed.
        ///
        /// - Parameters:
        ///   - index: The index of the line to change.
        ///   - line: The new text of the line.
        /// - Returns: The lines.
        static func bodyLines(changing index: Int, to line: String) -> [String] {
            UndoTests.lines(UndoTests.bodyLines, changing: index, to: line)
        }

        /// Makes an `updateTask` field that gives a task the lines of ``UndoTests/bodyLines`` with one line changed.
        ///
        /// - Parameters:
        ///   - index: The index of the line to change.
        ///   - line: The new text of the line.
        ///   - task: The ULID of the task.
        /// - Returns: The field.
        static func lineField(changing index: Int, to line: String, of task: ULID) -> String {
            UndoTests.bodyField(bodyLines(changing: index, to: line), of: task)
        }

        // MARK: - Queries

        /// Runs a query in the session of a branch, and expects that it gives no error.
        ///
        /// - Parameters:
        ///   - query: The query document.
        ///   - branch: The branch. The query runs on a copy of its session.
        /// - Returns: The `data` of the response.
        static func data(of query: String, in branch: Branch) async throws -> Map {
            var session = branch.session
            return try await ChangeBuilderTests.run(query, in: &session).data ?? .null
        }

        /// Queries one task of the board of a branch.
        ///
        /// - Parameters:
        ///   - task: The ULID of the task.
        ///   - selection: The selection of the task field.
        ///   - branch: The branch.
        /// - Returns: The task object of the response.
        static func task(_ task: ULID, selecting selection: String, in branch: Branch) async throws -> Map {
            try await data(of: CommentTests.taskQuery(of: task, selecting: selection), in: branch)["board"]["task"]
        }

        /// Gives the ids of a list of node objects of a response.
        ///
        /// - Parameter list: The list.
        /// - Returns: The `id` of each object.
        static func ids(in list: Map) -> Set<String> {
            HistoryTests.values(named: "id", of: list.array ?? [])
        }

        /// Gives the GraphQL ids of tags.
        ///
        /// - Parameter slugs: The slugs of the tags.
        /// - Returns: The full URI of each tag.
        static func tagIDs(_ slugs: String...) -> Set<String> {
            Set(slugs.map { slug in ColumnActorTests.id(of: .tag(slug: slug)) })
        }

        /// Gives the text lines of the body of a task.
        ///
        /// - Parameters:
        ///   - task: The ULID of the task.
        ///   - branch: The branch.
        /// - Returns: The lines, with no line break.
        static func bodyLines(of task: ULID, in branch: Branch) async throws -> [String] {
            let body = try #require(try await Self.task(task, selecting: bodySelection, in: branch)["body"].string)
            return body.split(separator: EventLog.lineBreak).map(String.init)
        }

        /// Gives the virtual tags of a task.
        ///
        /// - Parameters:
        ///   - task: The ULID of the task.
        ///   - branch: The branch.
        /// - Returns: The names of the virtual tags.
        static func virtualTags(of task: ULID, in branch: Branch) async throws -> [String] {
            let tags = try await Self.task(task, selecting: "{ virtualTags }", in: branch)["virtualTags"]
            return (tags.array ?? []).compactMap(\.string)
        }

        // MARK: - Body conflict

        /// Makes the two branches of the conflict tests: the main branch gives the fixture task the lines of
        /// ``UndoTests/bodyLines``, then each branch changes the line ``mainLineIndex`` to a different text.
        ///
        /// - Parameter task: The ULID of the fixture task.
        /// - Returns: The two branches.
        static func conflictingBranches(of task: ULID) async throws -> (main: Branch, other: Branch) {
            try await branches(
                after: [UndoTests.bodyField(UndoTests.bodyLines, of: task)],
                runningOnMain: [lineField(changing: mainLineIndex, to: UndoTests.changedLine, of: task)],
                runningOnOther: [lineField(changing: mainLineIndex, to: UndoTests.laterChangedLine, of: task)]
            )
        }

        // MARK: - Tags

        @Test("Two branches add different tags to one task, and after the merge the task has both tags")
        func differentTagsMergeToBoth() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let merged = try await Self.mergedBoard(
                runningOnMain: [Self.tagField(naming: TagMutationTests.bug, of: task)],
                runningOnOther: [Self.tagField(naming: TaskOperationTests.feature, of: task)]
            )
            let tags = try await Self.task(task, selecting: Self.tagsSelection, in: merged)["tags"]
            #expect(Self.ids(in: tags) == Self.tagIDs(TagMutationTests.bug, TaskOperationTests.feature))
        }

        @Test("One branch renames bug to defect while the other adds bug to a task, and the task shows defect")
        func renameAndAddMergeToNewTag() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let merged = try await Self.mergedBoard(
                runningOnMain: [TagMutationTests.renameTag(from: TagMutationTests.bug, to: TagMutationTests.defect)],
                runningOnOther: [Self.tagField(naming: TagMutationTests.bug, of: task)]
            )
            let tags = try await Self.task(task, selecting: Self.tagsSelection, in: merged)["tags"]
            #expect(Self.ids(in: tags) == Self.tagIDs(TagMutationTests.defect))
        }

        // MARK: - Body

        @Test("Two branches change different lines of one body, and after the merge the body has both changes")
        func differentLinesMergeToBoth() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let mainField = Self.lineField(changing: Self.mainLineIndex, to: UndoTests.changedLine, of: task)
            let otherField = Self.lineField(changing: Self.otherLineIndex, to: UndoTests.laterChangedLine, of: task)
            let merged = try await Self.mergedBoard(
                after: [UndoTests.bodyField(UndoTests.bodyLines, of: task)],
                runningOnMain: [mainField],
                runningOnOther: [otherField]
            )
            let mainLines = Self.bodyLines(changing: Self.mainLineIndex, to: UndoTests.changedLine)
            let expected = UndoTests.lines(mainLines, changing: Self.otherLineIndex, to: UndoTests.laterChangedLine)
            #expect(try await Self.bodyLines(of: task, in: merged) == expected)
        }

        @Test("Two branches change the same line, and a merge in either order gives the same one conflict block")
        func sameLineGivesOneConflictBlock() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let (main, other) = try await Self.conflictingBranches(of: task)
            let mainFirst = try await Self.bodyLines(of: task, in: Self.merge(other, into: main))
            let otherFirst = try await Self.bodyLines(of: task, in: Self.merge(main, into: other))
            #expect(mainFirst.filter { line in line == UnifiedDiff.ConflictBlock.startMarker }.count == 1)
            let otherEdit = try #require(other.session.live.events.last { event in event.patch.edit != nil })
            #expect(mainFirst.contains(UnifiedDiff.ConflictBlock.endPrefix + otherEdit.id.ulidString))
            #expect(otherFirst == mainFirst)
        }

        @Test("A task with a conflict block from a merge has the virtual tag CONFLICT, and #CONFLICT finds it")
        func conflictBlockGivesConflictTag() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let (main, other) = try await Self.conflictingBranches(of: task)
            let merged = try await Self.merge(other, into: main)
            #expect(try await Self.virtualTags(of: task, in: merged).contains(Self.conflictTag))
            let query = ##"{ board { tasks(filter: "#\##(Self.conflictTag)") { edges { node { id } } } } }"##
            let edges = try await Self.data(of: query, in: merged)["board"]["tasks"]["edges"].array ?? []
            #expect(Self.ids(in: .array(edges.map { edge in edge["node"] })) == [ColumnActorTests.id(of: .task(task))])
        }

        @Test("A body update after a merge with a conflict block removes the block and the virtual tag CONFLICT")
        func bodyUpdateRemovesConflict() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let (main, other) = try await Self.conflictingBranches(of: task)
            var merged = try await Self.merge(other, into: main)
            let update = UndoTests.bodyField(UndoTests.bodyLines, of: task)
            try await HistoryTests.run(eachOf: [update], in: &merged.session)
            #expect(try await Self.bodyLines(of: task, in: merged) == UndoTests.bodyLines)
            #expect(try await !Self.virtualTags(of: task, in: merged).contains(Self.conflictTag))
        }

        // MARK: - Broken merged states

        @Test("Each task of a dependency cycle that two branches make is blocked, also by a task that is done")
        func dependencyCycleBlocksEachTask() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            var main = try await Self.mainBranch()
            let complete = TaskOperationTests.taskField(MutationName.completeTask, of: task)
            try await HistoryTests.run(eachOf: [AddUpdateTaskTests.addTask(with: ""), complete], in: &main.session)
            let second = try #require(ReplayPropertyTests.tasks(of: main.session).first { added in added != task })
            var other = try await Self.branch(copying: main, mintingAtStep: Self.otherBranchStep)
            let closeOnMain = AddUpdateTaskTests.updateTask(task, with: AddUpdateTaskTests.dependsOn(second))
            try await HistoryTests.run(eachOf: [closeOnMain], in: &main.session)
            let closeOnOther = AddUpdateTaskTests.updateTask(second, with: AddUpdateTaskTests.dependsOn(task))
            try await HistoryTests.run(eachOf: [closeOnOther], in: &other.session)
            let merged = try await Self.merge(other, into: main)
            for (blocked, blocker) in [(task, second), (second, task)] {
                let fields = try await Self.task(blocked, selecting: "{ ready blockedBy { id } }", in: merged)
                #expect(fields["ready"] == .bool(false))
                #expect(Self.ids(in: fields["blockedBy"]) == [ColumnActorTests.id(of: .task(blocker))])
            }
        }

        @Test("A task that one branch moves into a column that the other branch deletes shows in the first column")
        func taskInDeletedColumnShowsInFirstColumn() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let qa = ColumnActorTests.qaSlug
            let toQA = TaskOperationTests.moveInput(to: qa)
            let move = TaskOperationTests.taskField(MutationName.moveTask, of: task, with: toQA)
            let merged = try await Self.mergedBoard(
                after: [ColumnActorTests.addQA],
                runningOnMain: [CommentTests.nodeField(MutationName.deleteColumn, naming: qa)],
                runningOnOther: [move]
            )
            let column = try await Self.task(task, selecting: "{ column { id } }", in: merged)["column"]["id"]
            #expect(column == .string(ColumnActorTests.id(of: KanbanGraphTests.todoColumn)))
        }

        /// Makes the merged board of the rename cycle tests: the board has the tags `bug` and `defect`, and the
        /// fixture task has `bug`. One branch renames `bug` to `defect`, and the other renames `defect` to `bug`.
        ///
        /// - Parameter task: The ULID of the fixture task.
        /// - Returns: The merged board.
        static func renameCycleBoard(of task: ULID) async throws -> Branch {
            let bug = TagMutationTests.bug
            let defect = TagMutationTests.defect
            return try await mergedBoard(
                after: [TagMutationTests.addTag(named: defect), tagField(naming: bug, of: task)],
                runningOnMain: [TagMutationTests.renameTag(from: bug, to: defect)],
                runningOnOther: [TagMutationTests.renameTag(from: defect, to: bug)]
            )
        }

        @Test("After a merge that makes a rename cycle, the task tag is the first slug of its walk that repeats")
        func renameCycleStopsTaskTagAtRepeat() async throws {
            let task = try AddUpdateTaskTests.fixtureTask()
            let merged = try await Self.renameCycleBoard(of: task)
            let tags = try await Self.task(task, selecting: Self.tagsSelection, in: merged)["tags"]
            #expect(Self.ids(in: tags) == Self.tagIDs(TagMutationTests.bug))
        }

        @Test("After a merge that makes a rename cycle, Board.tags lists each tag where a walk stops")
        func renameCycleListsEachStop() async throws {
            let merged = try await Self.renameCycleBoard(of: try AddUpdateTaskTests.fixtureTask())
            let tags = try await Self.data(of: "{ board { tags { id } } }", in: merged)["board"]["tags"]
            #expect(Self.ids(in: tags) == Self.tagIDs(TagMutationTests.bug, TagMutationTests.defect))
        }
    }
}
