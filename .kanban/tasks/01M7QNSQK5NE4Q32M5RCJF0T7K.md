---
assignees:
- claude-code
position_column: done
position_ordinal: ffcc80
title: Set C++ interoperability on the test target only
---
The loop at the end of `Package.swift` puts `.interoperabilityMode(.Cxx)` on each target, also on the library target. Thus each Swift-only consumer of `FoundationModelsKanban` does not compile ("module 'FoundationModelsKanban' was built with C++ interoperability enabled"). The CI of FoundationModelsACPClient is red since 2026-11-16. Brief: `../.briefs/kanban-cxx-interop.md`.

## Steps
- [ ] Set the mode only on the test target (`where target.type == .test`). Only the test target links FoundationModelsMultitool, which reaches llama.cpp.
- [ ] Remove the mode from `IntegrationTests/Package.swift`. That package links only the library and Extras, so it is a Swift-only consumer. The CI unit job builds it on each run.
- [ ] Add a manifest test: the library target has no C++ interoperability, and the integration package has none.
- [ ] `swift build`, `swift test`, and the build of `IntegrationTests` pass.
- [ ] Push, and send the sha to foundationmodelsacpclient-1d and testudoapp-9a. #bug #build