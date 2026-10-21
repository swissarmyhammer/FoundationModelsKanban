---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Move the GraphQL layer to the Extras toolkit and align the GraphQL/Graphiti declarations with Extras
---
## What
Replace the kanban copies of toolkit parts with the FoundationModelsExtras GraphQL toolkit (main 6670bc0 or later), per EXTRAS-9 rev 2 rule 2 and D74/D86. Spec: TestudoApp/features/packages/foundationmodels-kanban.md KANBAN-5, foundationmodels-extras.md EXTRAS-6/EXTRAS-9.

Delete these copies and use the Extras versions:
- `Sources/FoundationModelsKanban/GraphQL/CodedError.swift`: use the Extras `CodedError` protocol. Kanban has codes of its own, so the kanban error enum stays and conforms to it.
- `ResponseWarnings.swift`, `NameRewrite.swift` (NameRewrite/DocumentRewriter), `NameMatcher.swift`, `VariableReads.swift`, `JSONListText.swift`
- the DateTime/JSON scalars in `Scalars.swift`: use `addToolkitScalars()`
- the kanban subscription refusal in `KanbanTool`: use `GraphQLToolkitError.subscriptionNotInTool` through `GraphQLTool.answer`
- the run/response code in `Tool/KanbanGraph.swift` (`execute`, `subscribe`, the response type near line 1442): use `GraphQLRunContext`, `respond` and `subscribe`
- the alias tables in `FieldAliases.swift` go to `GraphQLNameRules`, so rewrites still show in `extensions.rewrites`

Kanban-only parts stay: `RemovedParameters.swift` (old Rust parameter compat), the board schema and resolvers, the alias tables, the `board { … }` root container, `extensions.txn`, and the content of `extensions.warnings`.

Package.swift (EXTRAS-9 rev 2 rule 2, the same as ACPAgent): keep declaring GraphQL and Graphiti, but only with the Extras URLs and Extras version floors (today `https://github.com/GraphQLSwift/GraphQL.git` from 4.3.0 and `https://github.com/GraphQLSwift/Graphiti.git` from 3.1.0, which kanban already has). Rewrite the manifest comments to say that the pins follow Extras and are not their own choice. The 57 `import GraphQL`/`import Graphiti` lines stay.

## Acceptance Criteria
- [ ] No file under Sources/FoundationModelsKanban/GraphQL duplicates a toolkit part (CodedError protocol, ResponseWarnings, NameRewrite, DocumentRewriter, NameMatcher, VariableReads, JSONListText, DateTime/JSON scalars)
- [ ] The GraphQL and Graphiti declarations in Package.swift use the same URLs and floors as FoundationModelsExtras/Package.swift
- [ ] Alias names still rewrite and show in `extensions.rewrites`; old Rust parameter names still work
- [ ] `extensions.txn` and `extensions.warnings` are unchanged for existing calls
- [ ] A subscription through KanbanTool gives `SUBSCRIPTION_NOT_IN_TOOL`, with a hint that names the query to read again (rule 10)

## Tests
- [ ] The full existing suite is green (`swift test`), with no response JSON drift except intentional changes listed in the commit
- [ ] The existing alias/rewrite, warnings and Rust-compat tests pass unchanged