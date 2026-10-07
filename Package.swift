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
// sorts the keys of each object, so it names this type directly.
let collectionsPackage = "swift-collections"

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
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: "Logging", package: loggingPackage),
                .product(name: graphQLPackage, package: graphQLPackage),
                .product(name: graphitiPackage, package: graphitiPackage),
                .product(name: "OrderedCollections", package: collectionsPackage),
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
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ],
    // Swift 6 language mode. It turns on the complete strict concurrency
    // checks for each target.
    swiftLanguageModes: [.v6]
)
