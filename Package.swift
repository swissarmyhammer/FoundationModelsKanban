// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Repeated identifiers are named constants, so the manifest has a single
// source of truth for each identifier.
let packageName = "FoundationModelsKanban"

// The logging API (the OpenTelemetry design of 2026-09-28). The library links
// the API only and bootstraps no backend. Until a host executable bootstraps a
// backend, each logger of the library does nothing.
let loggingPackage = "swift-log"

// The GraphQL engine: the parser, the validator, and the executor (plan.md
// §12, item 9). FoundationModelsExtras holds the GraphQL toolkit of the family
// and owns the pin of this package (EXTRAS-9 rev 2, rule 2). Extras does not
// re-export it, and a target can link only a product of a package that its own
// manifest declares, so this manifest declares it too. The URL and the version
// floor follow Extras; they are not a choice of this package. The same URL keeps
// one package identity, so `Package.resolved` holds one copy.
let graphQLPackage = "GraphQL"

// The version floor of `graphQLPackage`: the floor that FoundationModelsExtras
// declares.
let graphQLVersionFloor: Version = "4.3.0"

// The schema builder. It makes the GraphQL schema from Swift types, so that
// the Swift types are the one source of truth (plan.md §12, item 9). As for
// `graphQLPackage`, the URL and the version floor follow FoundationModelsExtras,
// which owns the pin.
let graphitiPackage = "Graphiti"

// The version floor of `graphitiPackage`: the floor that FoundationModelsExtras
// declares.
let graphitiVersionFloor: Version = "3.1.0"

// The GitHub organization of the GraphQL engine and the schema builder, as the
// manifest of FoundationModelsExtras names it.
let graphQLSwiftOrg = "https://github.com/GraphQLSwift/"

// The ordered dictionary that a GraphQL `Map` object holds. A patch value
// sorts the keys of each object, so it names this type directly. The loader
// also uses its `Heap` for the k-way merge of the event lists (plan.md §5.3).
let collectionsPackage = "swift-collections"

// The time-sortable identifier package. It is the same package and the same
// version floor as FoundationModelsMultitool (plan.md §8). Each task, each
// comment, each event and each transaction has a ULID (plan.md §3.2, §5.1).
let ulidPackage = "ULID.swift"

// The parser-combinator library of the filter language (plan.md §6.3, §12 item
// 24). It is the Swift library that is most like `chumsky`, which the Rust
// filter parser uses. The filter parser does not use the `CasePaths` trait,
// which the package turns on by default, so the dependency turns off all traits.
// Thus the build does not compile swift-syntax for the CasePaths macros.
let parsingPackage = "swift-parsing"

// The ranked search of `searchTasks` (plan.md §6.4, §12 item 6). The package
// also brings FoundationModelsRanker (BM25, trigram, cosine, and RRF), which it
// re-exports.
let metadataRegistryPackage = "FoundationModelsMetadataRegistry"

// The embedder protocol `PooledEmbedding` of `searchTasks` (plan.md §6.4).
// FoundationModelsMetadataRegistry takes this protocol, but it does not
// re-export it. Thus the library names this package to name the type. The
// package is already in the graph through FoundationModelsMetadataRegistry.
let extrasPackage = "FoundationModelsExtras"

// The code mode host of the tests (plan.md §9). The tests register
// `KanbanTool` in a `MultiTool` and run a `runCode` script against it. Only the
// test target links this package. The library does not depend on it.
let multitoolPackage = "FoundationModelsMultitool"

// The URL base of the sibling packages of the swissarmyhammer family. The same
// base as FoundationModelsCodeContext uses.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

let package = Package(
    name: packageName,
    // Commit to macOS 27. FoundationModels v2 and the sibling packages need
    // this floor.
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        ),
    ],
    dependencies: [
        // The same version ranges as FoundationModelsCodeContext,
        // FoundationModelsExtras and FoundationModelsACPClient, so that one
        // graph resolves each package to one version. Each sibling package
        // that a later step adds is referenced by URL, not by a local path,
        // for the CI reason that FoundationModelsCodeContext states.
        .package(url: "https://github.com/apple/\(loggingPackage).git", from: "1.15.1"),
        // The GraphQL engine and the schema builder follow
        // FoundationModelsExtras: its URLs and its version floors.
        .package(url: "\(graphQLSwiftOrg)\(graphQLPackage).git", from: graphQLVersionFloor),
        .package(url: "\(graphQLSwiftOrg)\(graphitiPackage).git", from: graphitiVersionFloor),
        .package(url: "https://github.com/apple/\(collectionsPackage).git", from: "1.0.0"),
        .package(url: "https://github.com/yaslab/\(ulidPackage).git", from: "1.3.1"),
        .package(url: "https://github.com/pointfreeco/\(parsingPackage).git", from: "0.15.2", traits: []),
        .package(url: "\(swissArmyHammerOrg)\(metadataRegistryPackage).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(extrasPackage).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(multitoolPackage).git", branch: "main"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: "Logging", package: loggingPackage),
                .product(name: graphQLPackage, package: graphQLPackage),
                .product(name: graphitiPackage, package: graphitiPackage),
                .product(name: "OrderedCollections", package: collectionsPackage),
                .product(name: "HeapModule", package: collectionsPackage),
                .product(name: "ULID", package: ulidPackage),
                .product(name: "Parsing", package: parsingPackage),
                .product(name: metadataRegistryPackage, package: metadataRegistryPackage),
                .product(name: extrasPackage, package: extrasPackage),
            ],
            path: "Sources/\(packageName)",
            // The system prompt of the filter agent (divergence.md §17, "A smart
            // prompt"). The file is a copy at the top of the resource bundle, so
            // `Bundle.module` finds it by its name.
            resources: [
                .copy("Resources/FilterAgentPrompt.md")
            ]
        ),
        // Swift Testing only (plan.md §11). This target holds the unit tests,
        // which need no external system.
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                // The tests give variables to the engine as GraphQL `Map`
                // values, and they call the scalar types of the schema.
                .product(name: graphQLPackage, package: graphQLPackage),
                // The warnings tests add a test field to the Graphiti builder
                // of the public schema.
                .product(name: graphitiPackage, package: graphitiPackage),
                // The identity tests make and read `ULID` values.
                .product(name: "ULID", package: ulidPackage),
                // The search tests give a fake `PooledEmbedding` to the engine,
                // and the GraphQL tests read the types of the GraphQL toolkit.
                .product(name: extrasPackage, package: extrasPackage),
                // The code mode tests run `KanbanTool` in a `MultiTool`.
                .product(name: multitoolPackage, package: multitoolPackage),
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ],
    // Swift 6 language mode. It turns on the complete strict concurrency
    // checks for each target.
    swiftLanguageModes: [.v6]
)
