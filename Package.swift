// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Repeated identifiers are named constants, so the manifest has a single
// source of truth for each identifier.
let packageName = "FoundationModelsKanban"

// The name of the command-line executable. `kanban '<document>'` runs a
// GraphQL document against the board of the current directory (plan.md §7.2).
let cliName = "kanban"

// The logging API (the OpenTelemetry design of 2026-09-28). The library links
// the API only and bootstraps no backend. Until a host executable bootstraps a
// backend, each logger of the library does nothing.
let loggingPackage = "swift-log"

// The command-line parser of the `kanban` executable.
let argumentParserPackage = "swift-argument-parser"

// The GraphQL engine: the parser, the validator, and the executor (plan.md
// §12, item 9).
let graphQLPackage = "GraphQL"

// The schema builder. It makes the GraphQL schema from Swift types, so that
// the Swift types are the one source of truth (plan.md §12, item 9).
let graphitiPackage = "Graphiti"

// The ordered dictionary that a GraphQL `Map` object holds. The `JSON` scalar
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
        .executable(
            name: cliName,
            targets: [cliName]
        ),
    ],
    dependencies: [
        // The same version ranges as FoundationModelsCodeContext,
        // FoundationModelsExtras and FoundationModelsACPClient, so that one
        // graph resolves each package to one version. Each sibling package
        // that a later step adds is referenced by URL, not by a local path,
        // for the CI reason that FoundationModelsCodeContext states.
        .package(url: "https://github.com/apple/\(loggingPackage).git", from: "1.15.1"),
        .package(url: "https://github.com/apple/\(argumentParserPackage).git", from: "1.8.0"),
        .package(url: "https://github.com/GraphQLSwift/\(graphQLPackage).git", from: "4.3.0"),
        .package(url: "https://github.com/GraphQLSwift/\(graphitiPackage).git", from: "3.1.0"),
        .package(url: "https://github.com/apple/\(collectionsPackage).git", from: "1.0.0"),
        .package(url: "https://github.com/yaslab/\(ulidPackage).git", from: "1.3.1"),
        .package(url: "https://github.com/pointfreeco/\(parsingPackage).git", from: "0.15.2", traits: []),
        .package(url: "\(swissArmyHammerOrg)\(metadataRegistryPackage).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(extrasPackage).git", branch: "main"),
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
            path: "Sources/\(packageName)"
        ),
        // The `kanban` CLI. It is a thin layer over the public API of the
        // library, and it is not part of the library product.
        .executableTarget(
            name: cliName,
            dependencies: [
                .target(name: packageName),
                .product(name: "ArgumentParser", package: argumentParserPackage),
            ],
            path: "Sources/\(cliName)"
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
                // The identity tests make and read `ULID` values.
                .product(name: "ULID", package: ulidPackage),
                // The search tests give a fake `PooledEmbedding` to the engine.
                .product(name: extrasPackage, package: extrasPackage),
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ],
    // Swift 6 language mode. It turns on the complete strict concurrency
    // checks for each target.
    swiftLanguageModes: [.v6]
)
