// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, of its library product, and of the directory that `..` holds.
///
/// The root manifest holds the same name in its own `packageName` constant.
private let productPackageName = "FoundationModelsKanban"

/// The package of `ModelPool` and `PooledModel`. The model test loads Qwen 3.8 with them, as a FoundationModels
/// `LanguageModel`. The root manifest names the same package in its own `extrasPackage` constant, with the same URL and
/// branch. A package can name only the products of a package that it declares, thus this package declares it again.
private let extrasPackageName = "FoundationModelsExtras"

/// The URL base of the sibling packages of the swissarmyhammer family. The root manifest holds the same base.
private let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// The SwiftPM manifest of the integration suite of FoundationModelsKanban.
///
/// **Why this is a package of its own.** The org test contract (the README of swissarmyhammer/workflows) says:
/// `swift test` at the root runs all the unit tests, and only the unit tests. An environment variable must not select
/// the tests. SwiftPM has no manifest setting that keeps a target out of the default run, so each test target of the
/// root package runs on a bare `swift test`. The root manifest does not name this package, so the root `swift test`
/// cannot see it. Thus the split is a property of the build graph, not a convention. Nothing here reads the
/// environment.
///
/// The two commands are:
///
///     swift test                                     # unit tests
///     swift test --package-path IntegrationTests     # this suite
///
/// **What this suite holds.** The tests that need a real external system, for example the real model
/// `mlx-community/Qwen3.8-27B-mxfp4`, which MLX runs. The first test is a smoke test: it makes a `KanbanGraph` in a
/// temporary git repo and reads the board. Thus the package builds and runs on its own.
///
/// **The compile coupling that CI needs.** The root build does not compile the files of this package.
/// `.github/workflows/ci.yml` gives `integration-package-path: IntegrationTests` to the shared `swift-ci.yaml`
/// workflow. That input makes the unit job of the shared workflow build this package on each run, and makes the
/// integration job run it.
///
/// **The pinned versions.** The root package follows the `main` branch of its sibling packages, and the committed
/// `../Package.resolved` pins one revision of each. A new resolution of this package gets the newest `main`, which
/// can have an API that the root sources do not compile against. Thus `Package.resolved` of this package is
/// committed, and it pins the same revisions as `../Package.resolved`. When the root pins change, copy them here.
let package = Package(
    name: "\(productPackageName)IntegrationTests",
    // Commit to macOS 27, the same floor as `../Package.swift`. A lower floor here does not resolve against it.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "\(swissArmyHammerOrg)\(extrasPackageName).git", branch: "main"),
    ],
    targets: [
        // The integration suite. It links the library product of the root package, and the Extras product that
        // loads the real model of the model test.
        .testTarget(
            name: "\(productPackageName)IntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName),
                .product(name: extrasPackageName, package: extrasPackageName),
            ],
            path: "Tests/\(productPackageName)IntegrationTests"
        )
    ],
    // Swift 6 language mode, the same as the root package. It turns on the complete strict concurrency checks.
    swiftLanguageModes: [.v6]
)
