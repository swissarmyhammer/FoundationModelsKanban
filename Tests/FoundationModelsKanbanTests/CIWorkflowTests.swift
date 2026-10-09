import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape of the sibling packages.
///
/// The workflow has one job. That job calls the shared `swift-ci.yaml` workflow of `swissarmyhammer/workflows` and
/// gives it two inputs:
///
/// - `integration-package-path` names the nested `IntegrationTests/` package. The root manifest does not name that
///   package, so the root build does not compile it. With this input, the unit job of the shared workflow builds the
///   package on each run, and the integration job runs it.
/// - `integration-metallib-glob` finds the `default.metallib` that SwiftPM puts in the Cmlx bundle. The integration
///   suite runs the real model `mlx-community/Qwen3.8-27B-mxfp4` through `PooledModel` of FoundationModelsExtras, and
///   MLX needs that shader library beside each `.xctest` bundle.
///
/// No other `integration-*` input is permitted. `integration-gate-env` is LEGACY: it selects a suite with an
/// environment variable, and the shared workflow stops the run when it is given beside the package path.
///
/// The test reads the YAML as lines, the same as the sibling packages, and adds no package dependency. An edit that
/// points `uses:` to a different workflow, removes or changes one of the two inputs, adds an input, changes the
/// triggers, or adds a job makes this suite fail.
@Suite("CI workflow")
struct CIWorkflowTests {
    /// The workflow file, relative to the repository root.
    private static let workflowPath = ".github/workflows/ci.yml"

    /// The input that names the nested integration package, with the colon that ends the key.
    private static let integrationPackagePathKey = "integration-package-path:"

    /// The input that finds the mlx-swift metallib, with the colon that ends the key.
    private static let integrationMetallibGlobKey = "integration-metallib-glob:"

    /// The prefix of each input that controls the integration job of the shared workflow.
    private static let integrationInputPrefix = "integration-"

    /// The lines that the workflow must hold, with no indent: the call to the shared workflow and its two inputs.
    private static let requiredLines = [
        "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main",
        "\(integrationPackagePathKey) IntegrationTests",
        #"\#(integrationMetallibGlobKey) "*Cmlx*/default.metallib""#,
    ]

    /// The `on:` block, line by line with its indent: a push to `main`, each pull request, and a run by hand.
    private static let triggerBlock = [
        "on:",
        "  push:",
        "    branches: [main]",
        "  pull_request:",
        "  workflow_dispatch:",
    ]

    /// The keys of the jobs, with their indent: one job, which calls the shared workflow.
    private static let jobKeys = ["  ci:"]

    /// The workflow holds each line of `requiredLines`.
    @Test("ci.yml holds each required line", arguments: requiredLines)
    func holdsTheLine(_ line: String) throws {
        let lines = try Self.workflowLines().map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(lines.contains(line), "ci.yml must hold the line \(line)")
    }

    /// The `on:` block of the workflow is the same as `triggerBlock`, and holds no other trigger.
    @Test("ci.yml runs on a push to main, on each pull request, and by hand")
    func runsOnTheSameTriggers() throws {
        let lines = try Self.workflowLines()
        let onIndex = try #require(lines.firstIndex(of: "on:"), "ci.yml has no top-level \"on:\" key.")
        let block = lines[onIndex...].prefix { !$0.isEmpty }.map(String.init)

        #expect(block == Self.triggerBlock, "ci.yml must have the \"on:\" block \(Self.triggerBlock); found \(block)")
    }

    /// The workflow gives the shared workflow no `integration-*` input other than the two of `requiredLines`.
    @Test("ci.yml gives the shared workflow no other integration-* input")
    func givesNoOtherIntegrationInput() throws {
        let allowedKeys = [Self.integrationPackagePathKey, Self.integrationMetallibGlobKey]
        // GitHub Actions compares a `with:` key with the `inputs:` of the called workflow without case. Thus the
        // test compares in lowercase, so that `Integration-Gate-Env:` cannot pass.
        let otherInputs = try Self.workflowLines()
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { key in
                key.hasPrefix(Self.integrationInputPrefix) && !allowedKeys.contains { key.hasPrefix($0) }
            }

        #expect(
            otherInputs.isEmpty,
            """
            ci.yml must give \(allowedKeys) and no other integration-* input: no environment variable selects a \
            suite; found: \(otherInputs)
            """
        )
    }

    /// The workflow has the jobs of `jobKeys` and no repo-local test job.
    @Test("ci.yml has one job, which calls the shared workflow")
    func hasOneJob() throws {
        let lines = try Self.workflowLines()
        let jobsIndex = try #require(lines.firstIndex(of: "jobs:"), "ci.yml has no top-level \"jobs:\" key.")
        // A job key has an indent of two spaces, for example "  ci:". The children of "on:" have the same shape,
        // thus the test reads only the lines after "jobs:".
        let jobKeyPattern = try Regex(#"^  [a-zA-Z0-9_-]+:$"#)
        let jobKeys = lines[lines.index(after: jobsIndex)...]
            .filter { $0.wholeMatch(of: jobKeyPattern) != nil }
            .map(String.init)

        #expect(jobKeys == Self.jobKeys, "ci.yml must have the jobs \(Self.jobKeys); found \(jobKeys)")
    }

    /// Reads the workflow file from the repository root.
    ///
    /// - Returns: each line of the workflow file, with its indent.
    /// - Throws: an error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        try RepositoryFile.lines(at: workflowPath)
    }
}
