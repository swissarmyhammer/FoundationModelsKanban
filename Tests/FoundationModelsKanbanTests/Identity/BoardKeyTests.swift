import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the board key: the normalization of a git remote URL, and the read of the key from a git repo (plan.md
/// §3.2, §12 item 4).
@Suite("Board keys")
struct BoardKeyTests {
    /// The key that each form of the test remote gives.
    static let expectedKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The HTTPS form of the test remote.
    static let httpsRemote = "https://github.com/swissarmyhammer/FoundationModelsKanban.git"

    /// The SSH form of the test remote.
    static let sshRemote = "git@github.com:swissarmyhammer/FoundationModelsKanban.git"

    /// The forms of one remote. Each form must give ``expectedKey``.
    static let remoteForms = [
        httpsRemote,
        sshRemote,
        "ssh://git@github.com/swissarmyhammer/FoundationModelsKanban.git",
        "ssh://git@github.com:22/swissarmyhammer/FoundationModelsKanban.git",
        "https://github.com/swissarmyhammer/FoundationModelsKanban",
        "https://GitHub.com/swissarmyhammer/FoundationModelsKanban.git/",
        "HTTPS://github.com/swissarmyhammer/FoundationModelsKanban.git",
        "https://reader@github.com:443/swissarmyhammer/FoundationModelsKanban.git",
        "git@github.com:/swissarmyhammer/FoundationModelsKanban.git",
        "github.com:swissarmyhammer/FoundationModelsKanban",
        "  git@github.com:swissarmyhammer/FoundationModelsKanban.git\n",
    ]

    // MARK: - Normalization

    @Test("SSH, HTTPS, and ssh:// forms of one remote give the same key", arguments: remoteForms)
    func remoteFormsGiveSameKey(remote: String) throws {
        #expect(try BoardKey(remoteURL: remote).description == Self.expectedKey)
    }

    @Test("The host changes to lowercase, and the owner and the repo keep their case")
    func hostIsLowercaseAndPathKeepsCase() throws {
        let key = try BoardKey(remoteURL: "git@GitHub.COM:Owner/Repo.git")
        #expect(key.description == "github.com/Owner/Repo")
    }

    @Test("A remote with more than two path segments keeps each segment")
    func nestedGroupKeepsEachSegment() throws {
        let key = try BoardKey(remoteURL: "git@gitlab.com:group/subgroup/repo.git")
        #expect(key.description == "gitlab.com/group/subgroup/repo")
    }

    @Test(
        "A remote with no host, no path, or an empty path segment is an invalid remote URL",
        arguments: [
            "",
            "/srv/git/repo.git",
            "../repo.git",
            "file:///srv/git/repo.git",
            "https://github.com/",
            "https://github.com/.git",
            "git@github.com:",
            "https://github.com/owner//repo.git",
            "https:///owner/repo.git",
        ]
    )
    func remoteWithoutHostOrPathThrows(remote: String) {
        #expect(throws: BoardKeyError.invalidRemoteURL(url: remote)) {
            try BoardKey(remoteURL: remote)
        }
    }

    @Test("A repo with no remote has the key local/<directory-name>")
    func localKeyHasDirectoryName() {
        #expect(BoardKey(localDirectoryName: "my-repo").description == "local/my-repo")
    }

    @Test("A key from a remote is a valid board key of a node URI")
    func keyMakesNodeURI() throws {
        let key = try BoardKey(remoteURL: Self.sshRemote)
        let uri = try NodeURI(parsing: "kanban://\(key)/column/doing")
        #expect(uri.boardKey == key.description)
    }

    // MARK: - Read from a repo

    @Test("A repo with no remote gives local/<directory-name>")
    func repoWithoutRemoteGivesLocalKey() throws {
        let sandbox = try GitSandbox()
        let repo = try sandbox.makeRepo(named: "my-repo")
        #expect(try BoardKey.read(fromRepoAt: repo) == BoardKey(localDirectoryName: "my-repo"))
    }

    @Test("A repo with an SSH origin and a repo with an HTTPS origin give the same key")
    func sshAndHTTPSOriginsGiveSameKey() throws {
        let sandbox = try GitSandbox()
        let sshRepo = try sandbox.makeRepo(named: "ssh-clone", origin: Self.sshRemote)
        let httpsRepo = try sandbox.makeRepo(named: "https-clone", origin: Self.httpsRemote)
        #expect(try BoardKey.read(fromRepoAt: sshRepo).description == Self.expectedKey)
        #expect(try BoardKey.read(fromRepoAt: httpsRepo).description == Self.expectedKey)
    }

    @Test("A subdirectory of a repo gives the key of the repo")
    func subdirectoryGivesKeyOfRepo() throws {
        let sandbox = try GitSandbox()
        let repo = try sandbox.makeRepo(named: "my-repo")
        let subdirectory = repo.appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        #expect(try BoardKey.read(fromRepoAt: subdirectory) == BoardKey(localDirectoryName: "my-repo"))
    }

    @Test("A worktree gives the same key as its main clone, with an origin")
    func worktreeWithOriginGivesKeyOfMainClone() throws {
        let sandbox = try GitSandbox()
        let repo = try sandbox.makeRepo(named: "main-clone", origin: Self.httpsRemote)
        let worktree = try sandbox.addWorktree(named: "feature-worktree", to: repo)
        #expect(try BoardKey.read(fromRepoAt: worktree) == BoardKey.read(fromRepoAt: repo))
        #expect(try BoardKey.read(fromRepoAt: worktree).description == Self.expectedKey)
    }

    @Test("A worktree gives the same key as its main clone, with no remote")
    func worktreeWithoutRemoteGivesKeyOfMainClone() throws {
        let sandbox = try GitSandbox()
        let repo = try sandbox.makeRepo(named: "main-clone")
        let worktree = try sandbox.addWorktree(named: "feature-worktree", to: repo)
        #expect(try BoardKey.read(fromRepoAt: worktree) == BoardKey(localDirectoryName: "main-clone"))
    }

    @Test("Each read gets the current origin, so a new remote gives a new key")
    func newOriginGivesNewKey() throws {
        let sandbox = try GitSandbox()
        let repo = try sandbox.makeRepo(named: "moved-repo", origin: Self.httpsRemote)
        let newOrigin = "git@gitlab.com:new-owner/moved-repo.git"
        try sandbox.runGit(withArguments: ["remote", "set-url", "origin", newOrigin], in: repo)
        #expect(try BoardKey.read(fromRepoAt: repo).description == "gitlab.com/new-owner/moved-repo")
    }

    @Test("A directory that is not in a git repo is a git failure")
    func directoryOutsideRepoThrows() throws {
        let sandbox = try GitSandbox()
        let directory = sandbox.root.appending(path: "plain-directory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect {
            try BoardKey.read(fromRepoAt: directory)
        } throws: { error in
            if case .gitFailed = error as? BoardKeyError { true } else { false }
        }
    }
}

// MARK: - Temporary repos

/// A temporary directory that holds the git repos of one test. The directory is removed when the sandbox ends.
///
/// The sandbox is a class, because its `deinit` removes the directory.
final class GitSandbox {
    /// The name and the email of the author of the first commit of each repo.
    static let identityArguments = ["-c", "user.name=Board Key Tests", "-c", "user.email=tests@example.invalid"]

    /// Turns off commit signatures, because the setup has no signing key.
    static let unsignedArguments = ["-c", "commit.gpgsign=false"]

    /// The temporary directory of the sandbox.
    let root: URL

    /// Makes an empty temporary directory.
    ///
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    init() throws {
        let name = "BoardKeyTests-\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Makes a git repo with one commit in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - origin: The URL of the `origin` remote, or `nil` for a repo with no remote.
    /// - Returns: The repo directory.
    /// - Throws: An error when the directory cannot be made, or when a git command cannot start or fails.
    func makeRepo(named name: String, origin: String? = nil) throws -> URL {
        let repo = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(withArguments: ["init", "--quiet"], in: repo)
        let commitArguments = ["commit", "--quiet", "--allow-empty", "-m", "Start"]
        try runGit(withArguments: Self.identityArguments + Self.unsignedArguments + commitArguments, in: repo)
        if let origin {
            try runGit(withArguments: ["remote", "add", "origin", origin], in: repo)
        }
        return repo
    }

    /// Adds a worktree of a repo in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the worktree directory. It is also the name of the new branch.
    ///   - repo: The main clone.
    /// - Returns: The worktree directory.
    /// - Throws: An error when the git command cannot start or fails.
    func addWorktree(named name: String, to repo: URL) throws -> URL {
        let worktree = root.appending(path: name, directoryHint: .isDirectory)
        try runGit(withArguments: ["worktree", "add", "--quiet", "-b", name, worktree.path], in: repo)
        return worktree
    }

    /// Runs a git command in a directory of the sandbox, and requires that it succeeds.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    /// - Throws: A ``BoardKeyError`` when git cannot start. An `ExpectationFailedError` when git exits with a failure
    ///   status.
    func runGit(withArguments arguments: [String], in directory: URL) throws {
        let result = try Git.run(withArguments: arguments, inDirectory: directory)
        try #require(result.status == Git.successStatus, "git \(arguments) failed: \(result.errorOutput)")
    }
}
