import Foundation
import Testing

/// Pins the C++ interoperability of the two manifests.
///
/// Only the test target of the root package takes `.interoperabilityMode(.Cxx)`, because only it links
/// FoundationModelsMultitool, which reaches the llama.cpp C++ modules. The library target must not take the mode. A
/// Swift module that imports a module with C++ interoperability must also build with C++ interoperability, so the mode
/// on the library breaks each Swift-only consumer.
///
/// The nested `IntegrationTests/` package links only the library and FoundationModelsExtras. It takes no mode, so it is
/// a Swift-only consumer, and the CI unit job builds it on each run.
@Suite("Manifest")
struct ManifestTests {
    /// The root manifest, relative to the repository root.
    private static let rootManifestPath = "Package.swift"

    /// The manifest of the nested integration package, relative to the repository root.
    private static let integrationManifestPath = "IntegrationTests/Package.swift"

    /// The setting that turns on C++ interoperability.
    private static let cxxSetting = ".interoperabilityMode(.Cxx)"

    /// The one loop of the root manifest that sets C++ interoperability. It selects the test targets only.
    private static let testTargetLoop = "for target in package.targets where target.type == .test {"

    /// Gives the code lines of a manifest, with no comment lines.
    private static func codeLines(at path: String) throws -> [String] {
        try RepositoryFile.lines(at: path)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
    }

    /// The root manifest sets C++ interoperability one time, in the loop over the test targets.
    @Test("Package.swift sets C++ interoperability on the test targets only")
    func rootSetsTheModeOnTestTargetsOnly() throws {
        let lines = try Self.codeLines(at: Self.rootManifestPath)
        let settingIndices = lines.indices.filter { lines[$0].contains(Self.cxxSetting) }

        #expect(settingIndices.count == 1, "Package.swift must set \(Self.cxxSetting) one time; found \(settingIndices.count)")
        let settingIndex = try #require(settingIndices.first)
        #expect(
            settingIndex > 0 && lines[settingIndex - 1] == Self.testTargetLoop,
            "The line before \(Self.cxxSetting) must be \(Self.testTargetLoop)"
        )
    }

    /// The integration package sets no C++ interoperability, so its build proves a Swift-only consumer.
    @Test("IntegrationTests/Package.swift sets no C++ interoperability")
    func integrationPackageSetsNoMode() throws {
        let lines = try Self.codeLines(at: Self.integrationManifestPath)

        #expect(
            !lines.contains { $0.contains(Self.cxxSetting) },
            "IntegrationTests/Package.swift must not set \(Self.cxxSetting)"
        )
    }
}
