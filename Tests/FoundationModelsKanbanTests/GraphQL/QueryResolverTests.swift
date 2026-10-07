import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the read side of the public schema: the node types and the board queries (plan.md §4.1). Each test runs a
/// GraphQL document against the board of ``QueryFixture``, and compares the response JSON.
@Suite("Query resolvers")
struct QueryResolverTests {
    /// The number of tasks of the fixture board.
    static let taskCount = 3

    /// The page size of the paging test: smaller than ``taskCount``, so that the tasks need two pages.
    static let pageSize = 2

    /// The number of ready tasks of the fixture board: the first task, and the done third task.
    static let readyCount = 2

    /// The percent of done tasks of the fixture board: one task of three, rounded.
    static let donePercent = 33

    /// The `data` part of a response to a `tasks` query: `{ board { tasks { … } } }`.
    struct TasksResponse: Decodable {
        /// The `data` object.
        struct DataObject: Decodable {
            /// The `board` object.
            let board: BoardObject
        }

        /// The `board` object.
        struct BoardObject: Decodable {
            /// The `tasks` connection.
            let tasks: Connection
        }

        /// The `tasks` connection.
        struct Connection: Decodable {
            /// The number of tasks in the full list.
            let totalCount: Int

            /// The tasks of the page.
            let edges: [Edge]

            /// The position of the page in the list.
            let pageInfo: PageInfoObject
        }

        /// One task of a page.
        struct Edge: Decodable {
            /// The task.
            let node: TaskObject
        }

        /// The fields of a task that the query selects.
        struct TaskObject: Decodable {
            /// The URI of the task.
            let id: String
        }

        /// The `pageInfo` object.
        struct PageInfoObject: Decodable {
            /// `true` when more tasks follow the page.
            let hasNextPage: Bool

            /// The cursor of the last task of the page.
            let endCursor: String?
        }

        /// The `data` object.
        let data: DataObject
    }

    /// Reads one page of tasks. The query gives `excludeDone: false`, so that the page can hold the done task.
    ///
    /// - Parameters:
    ///   - fixture: The board.
    ///   - cursor: The cursor after which the page starts, or `nil` for the first page.
    /// - Returns: The connection of the page.
    /// - Throws: An error when the response is not the expected JSON.
    static func page(of fixture: QueryFixture, after cursor: String?) async throws -> TasksResponse.Connection {
        let afterArgument = cursor.map { #", after: "\#($0)""# } ?? ""
        let response = try await fixture.respond(
            to: "{ board { tasks(first: \(pageSize), excludeDone: false\(afterArgument)) "
                + "{ totalCount edges { node { id } } pageInfo { hasNextPage endCursor } } } }"
        )
        return try JSONDecoder().decode(TasksResponse.self, from: Data(response.utf8)).data.board.tasks
    }

    @Test("A deep query from a task through dependsOn, comments, and author returns the nested graph")
    func deepQueryReturnsTheNestedGraph() async throws {
        let response = try await QueryFixture().respond(
            to: """
                { board { task(id: "\(QueryFixture.sigilRef(of: ReadinessFixture.second))") { title
                    dependsOn { title comments { body author { name } } } } } }
                """
        )
        let expected = #"{"data":{"board":{"task":{"title":"\#(QueryFixture.secondTitle)","#
            + #""dependsOn":[{"title":"\#(QueryFixture.firstTitle)","#
            + #""comments":[{"body":"\#(QueryFixture.commentBody)","#
            + #""author":{"name":"\#(QueryFixture.actorName)"}}]}]}}}}"#
        #expect(response == expected)
    }

    @Test("Each id in the output is a full kanban:// URI with the current board key")
    func eachIDIsAFullURI() async throws {
        let response = try await QueryFixture().respond(
            to: """
                { board { id columns { id } actors { id } tags { id }
                    task(id: "\(ReadinessFixture.first)") { id column { id } comments { id task { id } } } } }
                """
        )
        let columns = ReadinessFixture.defaultColumns.map { slug in
            #"{"id":"\#(QueryFixture.id(of: "column/\(slug)"))"}"#
        }
        let firstID = QueryFixture.id(ofTask: ReadinessFixture.first)
        let commentID = QueryFixture.id(of: "comment/\(ReadinessFixture.firstComment)")
        let expected = #"{"data":{"board":{"id":"\#(QueryFixture.id(of: "board"))","#
            + #""columns":[\#(columns.joined(separator: ","))],"#
            + #""actors":[{"id":"\#(QueryFixture.id(of: "actor/\(ReadinessFixture.author)"))"}],"#
            + #""tags":[{"id":"\#(QueryFixture.id(of: "tag/\(QueryFixture.tagSlug)"))"}],"#
            + #""task":{"id":"\#(firstID)","column":{"id":"\#(QueryFixture.id(of: "column/doing"))"},"#
            + #""comments":[{"id":"\#(commentID)","task":{"id":"\#(firstID)"}}]}}}}"#
        #expect(response == expected)
    }

    @Test("Paging with first and after returns each task one time, and totalCount counts all tasks")
    func pagingReturnsEachTaskOneTime() async throws {
        let fixture = try QueryFixture()
        let firstPage = try await Self.page(of: fixture, after: nil)
        let secondPage = try await Self.page(of: fixture, after: firstPage.endCursorOfPage())
        let ids = (firstPage.edges + secondPage.edges).map(\.node.id)
        let expected = [ReadinessFixture.second, ReadinessFixture.first, ReadinessFixture.third].map { text in
            QueryFixture.id(ofTask: text)
        }
        #expect(ids == expected)
        #expect(firstPage.totalCount == Self.taskCount)
        #expect(secondPage.totalCount == Self.taskCount)
        #expect(firstPage.pageInfo.hasNextPage)
        #expect(!secondPage.pageInfo.hasNextPage)
    }

    @Test("The tasks of the board are in column order, and then in ordinal order in a column")
    func tasksAreInColumnOrderThenOrdinalOrder() async throws {
        var fixture = try QueryFixture()
        let fourth = TaskNode(
            id: try DependencyMarkersTests.ulid(of: ReadinessFixture.fourth),
            fields: ReadinessFixture.fields(),
            title: ReadinessFixture.fourth,
            column: QueryFixture.edge(to: .column(slug: ReadinessFixture.doing)),
            ordinal: Ordinal(before: .first)
        )
        fixture.graph.update(with: .task(fourth))
        let response = try await fixture.respond(
            to: "{ board { tasks(excludeDone: false) { edges { node { title } } } } }"
        )
        let titles = [
            QueryFixture.secondTitle, ReadinessFixture.fourth, QueryFixture.firstTitle, QueryFixture.thirdTitle,
        ]
        let edges = titles.map { title in #"{"node":{"title":"\#(title)"}}"# }
        #expect(response == #"{"data":{"board":{"tasks":{"edges":[\#(edges.joined(separator: ","))]}}}}"#)
    }

    @Test("The derived fields of a task come from the readiness, the checklist, and the tags")
    func taskHasItsDerivedFields() async throws {
        let response = try await QueryFixture().respond(
            to: """
                { board { task(id: "\(ReadinessFixture.first)") { shortId ready virtualTags blocks { title }
                    blockedBy { title } progress { total completed } assignees { name } tags { name color } } } }
                """
        )
        let shortID = ShortID(ofULIDString: ReadinessFixture.first).value
        let color = AutoColor.color(forText: QueryFixture.tagSlug)
        let expected = #"{"data":{"board":{"task":{"shortId":"\#(shortID)","ready":true,"#
            + #""virtualTags":["READY","BLOCKING"],"blocks":[{"title":"\#(QueryFixture.secondTitle)"}],"#
            + #""blockedBy":[],"progress":{"total":2,"completed":1},"#
            + #""assignees":[{"name":"\#(QueryFixture.actorName)"}],"#
            + #""tags":[{"name":"\#(QueryFixture.tagSlug)","color":"\#(color)"}]}}}}"#
        #expect(response == expected)
    }

    @Test("A task that waits for a task that is not done is blocked by it")
    func blockedTaskNamesItsBlocker() async throws {
        let response = try await QueryFixture().respond(
            to: """
                { board { task(id: "\(ReadinessFixture.second)") { ready virtualTags blockedBy { title } } } }
                """
        )
        let expected = #"{"data":{"board":{"task":{"ready":false,"virtualTags":["BLOCKED"],"#
            + #""blockedBy":[{"title":"\#(QueryFixture.firstTitle)"}]}}}}"#
        #expect(response == expected)
    }

    @Test("A column, an actor, and a tag list their tasks")
    func columnActorAndTagListTheirTasks() async throws {
        let response = try await QueryFixture().respond(
            to: "{ board { columns { name order tasks { title } } "
                + "actors { tasks { title } } tags { tasks { title } } } }"
        )
        let columnTitles = [
            ReadinessFixture.todo: [QueryFixture.secondTitle], ReadinessFixture.doing: [QueryFixture.firstTitle],
            ReadinessFixture.done: [QueryFixture.thirdTitle],
        ]
        let columns = ReadinessFixture.defaultColumns.enumerated().map { order, slug in
            let tasks = columnTitles[slug, default: []].map { title in #"{"title":"\#(title)"}"# }
            return #"{"name":"","order":\#(order),"tasks":[\#(tasks.joined(separator: ","))]}"#
        }
        let firstTask = #"[{"tasks":[{"title":"\#(QueryFixture.firstTitle)"}]}]"#
        let expected = #"{"data":{"board":{"columns":[\#(columns.joined(separator: ","))],"#
            + #""actors":\#(firstTask),"tags":\#(firstTask)}}}"#
        #expect(response == expected)
    }

    @Test("The summary of the board counts its live tasks")
    func boardHasItsSummary() async throws {
        let response = try await QueryFixture().respond(
            to: "{ board { name summary { total ready blocked done percent } } }"
        )
        let expected = #"{"data":{"board":{"name":"\#(QueryFixture.boardName)","#
            + #""summary":{"total":\#(Self.taskCount),"ready":\#(Self.readyCount),"blocked":1,"done":1,"#
            + #""percent":\#(Self.donePercent)}}}}"#
        #expect(response == expected)
    }

    @Test("Query.board with the key of the current board returns the board")
    func boardByKeyReturnsTheBoard() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ board(id: "\#(DependencyMarkersTests.boardKey)") { name } }"#
        )
        #expect(response == #"{"data":{"board":{"name":"\#(QueryFixture.boardName)"}}}"#)
    }

    @Test("Query.board with the key of a different board returns null and an error")
    func boardByOtherKeyReturnsNull() async throws {
        let response = try await QueryFixture().respond(to: #"{ board(id: "local/other") { name } }"#)
        #expect(response.hasPrefix(#"{"data":{"board":null},"errors":["#))
        #expect(response.contains(#""path":["board"]"#))
    }

    @Test("Board.task with an unknown id returns null and an error")
    func unknownTaskReturnsNull() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ board { task(id: "\#(ReadinessFixture.ghost)") { title } } }"#
        )
        #expect(response.hasPrefix(#"{"data":{"board":{"task":null}},"errors":["#))
        #expect(response.contains(#""path":["board","task"]"#))
    }

    @Test("Board.tasks with an after cursor that names no task returns null and an error")
    func unknownCursorGivesAnError() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ board { tasks(after: "\#(ReadinessFixture.ghost)") { totalCount } } }"#
        )
        #expect(response.hasPrefix(#"{"data":{"board":{"tasks":null}},"errors":["#))
        #expect(response.contains(#""path":["board","tasks"]"#))
    }
}

extension QueryResolverTests.TasksResponse.Connection {
    /// Gives the cursor of the last task of the page.
    ///
    /// - Returns: The cursor.
    /// - Throws: An error when the page has no cursor.
    func endCursorOfPage() throws -> String {
        try #require(pageInfo.endCursor)
    }
}
