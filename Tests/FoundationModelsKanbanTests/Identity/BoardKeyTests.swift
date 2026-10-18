import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the board key: the normalization of a git remote URL, and the read of the key from a git repo (plan.md
/// §3.2, §12 item 4).
@Suite("Board keys", .watcherBudget)
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

    /// The `origin` URLs with no host: local paths and a `file://` URL. Each one gives the key of a repo with no
    /// remote.
    static let localOrigins = ["/srv/git/repo.git", "../upstream", "file:///srv/git/repo.git"]

    /// The name of the subfolder of a repo in the subfolder test.
    static let subfolderName = "Sources"

    /// The `origin` of the repo in the subfolder test: no remote, and a remote with a host.
    static let subfolderOrigins: [String?] = [nil, httpsRemote]

    /// The name of the folder that is not in a git repo.
    static let plainFolderName = "plain-directory"

    /// An `origin` URL with a host but no path. ``BoardKey/init(remoteURL:)`` refuses it, so the repo gets the key
    /// of a repo with no remote.
    static let pathlessOrigin = "https://example.com/"

    /// The name of the config file in the git directory of a repo.
    static let gitConfigFileName = "config"

    /// The text of a git config file that git cannot read: one line that is not a section and not a key.
    static let brokenConfigText = "not a config line\n"

    /// The standard error of git in a repo whose config file is ``brokenConfigText``.
    static let brokenConfigMessage = "fatal: bad config line 1 in file .git/config\n"

    /// The exit status of git after a fatal error.
    static let gitFatalStatus: Int32 = 128

    /// The SHA of a commit, for the test of the text of a root commit key.
    static let sampleCommit = "c83fae4e58ced3b4cddb5c4bf9f151b0df1d379b"

    /// The name of the file that a test stages in a repo with no commit.
    static let stagedFileName = "notes.txt"

    /// The text of the file that a test stages in a repo with no commit.
    static let stagedText = "staged, not committed\n"

    /// The text in the standard error of git when git has no identity for a commit.
    static let unknownIdentityMessage = "Author identity unknown"

    /// The command of git that makes the first commit of a repo with no commit.
    static let firstCommitCommand = "commit-tree"

    /// The branch that a root-commit test makes with `git checkout --orphan`.
    static let orphanBranch = "other-history"

    /// The places of a merge in the test of two root commits: `true` merges the orphan branch into the first
    /// branch, and `false` merges the first branch into the orphan branch. The two merges list the two root commits
    /// in opposite orders, so a key that takes the first root commit of the list fails one of them.
    static let mergeIntoFirstBranch = [true, false]

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

    @Test("A repo with no remote has the key local/<first 12 hex digits of the root commit>")
    func localKeyHasTwelveDigitsOfRootCommit() {
        #expect(BoardKey(rootCommit: Self.sampleCommit).description == "local/c83fae4e58ce")
    }

    @Test("A key from a remote is a valid board key of a node URI")
    func keyMakesNodeURI() throws {
        let key = try BoardKey(remoteURL: Self.sshRemote)
        let uri = try NodeURI(parsing: "kanban://\(key)/column/doing")
        #expect(uri.boardKey == key.description)
    }

    // MARK: - Read from a repo

    @Test("A repo with no remote gives local/<root commit>")
    func repoWithoutRemoteGivesRootCommitKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo")
        #expect(try await BoardKey.read(fromRepoAt: repo) == sandbox.headKey(of: repo))
    }

    @Test("Two clones and a worktree of a repo with no remote have the same key")
    func clonesWithoutRemoteGiveSameKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "first-clone")
        let clone = try await sandbox.cloneRepo(repo, named: "second-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: clone)
        let key = try await sandbox.headKey(of: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == key)
        #expect(try await BoardKey.read(fromRepoAt: clone) == key)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == key)
    }

    @Test("A repo with two root commits uses the lowest SHA", arguments: mergeIntoFirstBranch)
    func twoRootCommitsGiveLowestSHA(intoFirstBranch: Bool) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "merged-repo")
        try await sandbox.commit(message: "First history", in: repo)
        let firstBranch = try await GitSandbox.output(ofGit: ["symbolic-ref", "--short", "HEAD"], in: repo)
        let firstRoot = try await GitSandbox.headSHA(of: repo)
        try await GitSandbox.runGit(withArguments: ["checkout", "--quiet", "--orphan", Self.orphanBranch], in: repo)
        try await sandbox.commit(message: "Second history", in: repo)
        let secondRoot = try await GitSandbox.headSHA(of: repo)
        let (target, source) = intoFirstBranch ? (firstBranch, Self.orphanBranch) : (Self.orphanBranch, firstBranch)
        try await GitSandbox.runGit(withArguments: ["checkout", "--quiet", target], in: repo)
        try await sandbox.merge(source, in: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == BoardKey(rootCommit: min(firstRoot, secondRoot)))
    }

    // MARK: - First commit

    @Test("A new repo with no commit gets one empty first commit on its branch, and the key comes from that commit")
    func repoWithoutCommitGetsEmptyFirstCommit() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "new-repo")
        let branch = try await GitSandbox.output(ofGit: ["symbolic-ref", "HEAD"], in: repo)
        let key = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--count", branch], in: repo) == "1")
        #expect(try await GitSandbox.output(ofGit: ["ls-tree", "HEAD"], in: repo) == "")
        let message = try await GitSandbox.output(ofGit: ["log", "-1", "--format=%s"], in: repo)
        #expect(message == BoardKey.firstCommitMessage)
        #expect(try await key == sandbox.headKey(of: repo))
    }

    @Test("Two new repos that get their first commits at the same time, with the same author, get different keys")
    func firstCommitsAtSameTimeGiveDifferentKeys() async throws {
        let sandbox = try GitSandbox()
        let firstRepo = try await sandbox.makeEmptyRepo(named: "first-new-repo")
        let secondRepo = try await sandbox.makeEmptyRepo(named: "second-new-repo")
        let environment = GitSandbox.fixedDateEnvironment
        async let firstKey = BoardKey.read(fromRepoAt: firstRepo, gitEnvironment: environment)
        async let secondKey = BoardKey.read(fromRepoAt: secondRepo, gitEnvironment: environment)
        #expect(try await firstKey != secondKey)
    }

    @Test("The first commit does not take the staged files, and the working files do not change")
    func firstCommitKeepsStagedFiles() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "staged-repo")
        let file = repo.appending(path: Self.stagedFileName)
        try Self.stagedText.write(to: file, atomically: true, encoding: .utf8)
        try await GitSandbox.runGit(withArguments: ["add", Self.stagedFileName], in: repo)
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.output(ofGit: ["ls-tree", "-r", "--name-only", "HEAD"], in: repo) == "")
        let staged = try await GitSandbox.output(ofGit: ["diff", "--cached", "--name-only"], in: repo)
        #expect(staged == Self.stagedFileName)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.stagedText)
    }

    @Test("A repo with commits gets no new commit")
    func repoWithCommitsGetsNoNewCommit() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "old-repo")
        let head = try await GitSandbox.headSHA(of: repo)
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.headSHA(of: repo) == head)
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--count", "--all"], in: repo) == "1")
    }

    @Test("A repo with no commit and no git identity gives an error with the reason from git, and gets no commit")
    func firstCommitWithoutIdentityThrows() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "anonymous-repo", withIdentity: false)
        let environment = try sandbox.makeEnvironmentWithoutIdentity()
        let error = try await #require(throws: BoardKeyError.self) {
            try await BoardKey.read(fromRepoAt: repo, gitEnvironment: environment)
        }
        let failure = try #require(Self.gitFailure(of: error))
        #expect(failure.command == Self.firstCommitCommand)
        #expect(failure.message.contains(Self.unknownIdentityMessage))
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--all"], in: repo) == "")
    }

    /// Gives the command and the message of a ``BoardKeyError/gitFailed(arguments:status:message:)`` error.
    ///
    /// - Parameter error: The error.
    /// - Returns: The first argument of git and the standard error of git, or `nil` for each other error.
    static func gitFailure(of error: BoardKeyError) -> (command: String?, message: String)? {
        switch error {
        case .gitFailed(let arguments, _, let message): (arguments.first, message)
        case .invalidRemoteURL, .notARepo, .gitUnavailable, .gitTimedOut, .gitCancelled: nil
        }
    }

    @Test("A repo with an SSH origin and a repo with an HTTPS origin give the same key")
    func sshAndHTTPSOriginsGiveSameKey() async throws {
        let sandbox = try GitSandbox()
        let sshRepo = try await sandbox.makeRepo(named: "ssh-clone", origin: Self.sshRemote)
        let httpsRepo = try await sandbox.makeRepo(named: "https-clone", origin: Self.httpsRemote)
        #expect(try await BoardKey.read(fromRepoAt: sshRepo).description == Self.expectedKey)
        #expect(try await BoardKey.read(fromRepoAt: httpsRepo).description == Self.expectedKey)
    }

    @Test("A subfolder of a repo gives the key of the repo", arguments: subfolderOrigins)
    func subfolderGivesKeyOfRepo(origin: String?) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo", origin: origin)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: repo)
        #expect(try await BoardKey.read(fromRepoAt: subfolder) == BoardKey.read(fromRepoAt: repo))
    }

    @Test("A folder that is not in a git repo has no key: the read throws notARepo")
    func folderOutsideRepoThrowsNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        await #expect(throws: BoardKeyError.notARepo(path: folder.path)) {
            try await BoardKey.read(fromRepoAt: folder)
        }
    }

    // MARK: - Worktree top

    @Test("The worktree top of a subfolder of a repo is the top folder of the repo, with the path of the caller")
    func worktreeTopOfSubfolderIsRepo() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo")
        let subfolder = try GitSandbox.makeFolder(named: "\(Self.subfolderName)/Deep", in: repo)
        #expect(try await BoardKey.worktreeTop(of: subfolder).path == repo.standardizedFileURL.path)
    }

    @Test("The worktree top of a folder in a linked worktree is the top folder of that worktree")
    func worktreeTopOfLinkedWorktreeIsWorktree() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: worktree)
        #expect(try await BoardKey.worktreeTop(of: subfolder).path == worktree.standardizedFileURL.path)
    }

    @Test("A folder that is not in a git repo has no worktree top: the read throws notARepo")
    func worktreeTopOutsideRepoThrowsNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        await #expect(throws: BoardKeyError.notARepo(path: folder.path)) {
            try await BoardKey.worktreeTop(of: folder)
        }
    }

    @Test("A git failure in a repo throws gitFailed, and does not give a local key")
    func gitFailureInRepoThrows() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "broken-repo")
        let configFile = repo.appending(path: BoardKey.gitDirectoryName).appending(path: Self.gitConfigFileName)
        try Self.brokenConfigText.write(to: configFile, atomically: true, encoding: .utf8)
        let expected = BoardKeyError.gitFailed(
            arguments: BoardKey.repoPathsArguments,
            status: Self.gitFatalStatus,
            message: Self.brokenConfigMessage
        )
        await #expect(throws: expected) { try await BoardKey.read(fromRepoAt: repo) }
    }

    @Test("An origin with a host but no path gives local/<root commit>")
    func originWithoutPathGivesLocalKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: Self.pathlessOrigin)
        #expect(try await BoardKey.read(fromRepoAt: repo) == sandbox.headKey(of: repo))
    }

    @Test("An origin with no host gives local/<root commit>, also in a worktree", arguments: localOrigins)
    func originWithoutHostGivesLocalKey(origin: String) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: origin)
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let key = try await sandbox.headKey(of: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == key)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == key)
    }

    @Test("A worktree gives the same key as its main clone, with an origin")
    func worktreeWithOriginGivesKeyOfMainClone() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: Self.httpsRemote)
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let worktreeKey = try await BoardKey.read(fromRepoAt: worktree)
        let mainCloneKey = try await BoardKey.read(fromRepoAt: repo)
        #expect(worktreeKey == mainCloneKey)
        #expect(worktreeKey.description == Self.expectedKey)
    }

    @Test("A worktree gives the same key as its main clone, with no remote")
    func worktreeWithoutRemoteGivesKeyOfMainClone() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == sandbox.headKey(of: repo))
    }

    @Test("Each read gets the current origin, so a new remote gives a new key")
    func newOriginGivesNewKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "moved-repo", origin: Self.httpsRemote)
        let newOrigin = "git@gitlab.com:new-owner/moved-repo.git"
        try await GitSandbox.runGit(withArguments: ["remote", "set-url", "origin", newOrigin], in: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo).description == "gitlab.com/new-owner/moved-repo")
    }

    // MARK: - Engine

    @Test("An engine in a repo whose origin has no host gives local/<root commit>", arguments: localOrigins)
    func engineWithLocalOriginGivesLocalKey(origin: String) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: origin)
        let response = try await Self.keyResponse(ofEngineAt: repo)
        #expect(try await response == KanbanGraphTests.keyResponse(of: sandbox.headKey(of: repo)))
    }

    @Test("An engine in a new repo with no commit makes the first commit, and gives local/<root commit>")
    func engineInRepoWithoutCommitGivesRootCommitKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "new-repo")
        let response = try await Self.keyResponse(ofEngineAt: repo)
        #expect(try await response == KanbanGraphTests.keyResponse(of: sandbox.headKey(of: repo)))
    }

    @Test("An engine in a subfolder of a repo gives the key of the repo", arguments: subfolderOrigins)
    func engineInSubfolderGivesKeyOfRepo(origin: String?) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo", origin: origin)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: repo)
        let response = try await Self.keyResponse(ofEngineAt: subfolder)
        #expect(try await response == KanbanGraphTests.keyResponse(of: BoardKey.read(fromRepoAt: repo)))
    }

    @Test("An engine in a folder that is not in a git repo gives NOT_A_REPO for the key")
    func engineOutsideRepoGivesNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        let response = try await Self.keyResponse(ofEngineAt: folder)
        #expect(try response == KanbanError.notARepo(path: folder.path).responseJSON())
    }

    /// Runs ``KanbanGraphTests/keyQuery`` on an engine that reads the key from git, and closes the engine.
    ///
    /// - Parameter directory: The working directory of the engine.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot start or the query throws.
    private static func keyResponse(ofEngineAt directory: URL) async throws -> String {
        try await RepoBoardTests.respond(to: KanbanGraphTests.keyQuery, inWorkingDirectory: directory)
    }

    // MARK: - Git process

    /// The number of bytes that the flood command writes to the standard error. This is more than the buffer of a
    /// pipe, so a writer that nobody reads stops until a reader empties the pipe.
    static let floodSize = 200_000

    /// The word that the flood command writes to the standard output, on one line, after it writes the standard
    /// error.
    static let floodWord = "done"

    /// The arguments of a git alias that writes ``floodSize`` bytes to the standard error, and then ``floodWord`` to
    /// the standard output.
    static let floodArguments = ["-c", "alias.flood=!head -c \(floodSize) /dev/zero >&2; echo \(floodWord)", "flood"]

    /// The time that the slow command runs. This is much longer than ``shortGitLimit``.
    static let slowCommandDuration = Duration.seconds(slowCommandSeconds)

    /// The number of seconds in ``slowCommandDuration``.
    private static let slowCommandSeconds = 5

    /// The arguments of a git alias that runs for ``slowCommandDuration``.
    static let slowArguments = ["-c", "alias.slow=!sleep \(slowCommandDuration.components.seconds)", "slow"]

    /// The time limit of the slow command.
    static let shortGitLimit = Duration.milliseconds(shortGitLimitMilliseconds)

    /// The number of milliseconds in ``shortGitLimit``.
    private static let shortGitLimitMilliseconds = 300

    /// The number of git commands for each processor in the tests that run many git commands at the same time. A
    /// command that blocked the thread of its task would thus block each thread of Swift concurrency.
    static let commandsPerProcessor = 4

    /// The arguments of a git command that ends at once and writes to the standard output.
    static let versionArguments = ["--version"]

    /// The number of git commands in the tests that run many git commands at the same time.
    static var parallelCommandCount: Int {
        ProcessInfo.processInfo.activeProcessorCount * commandsPerProcessor
    }

    /// The time that a short sleep waits while many slow git commands run. It is much shorter than
    /// ``slowCommandDuration``.
    static let shortSleep = Duration.milliseconds(shortSleepMilliseconds)

    /// The number of milliseconds in ``shortSleep``.
    private static let shortSleepMilliseconds = 100

    /// The name of the file where the slow command writes the process id of git.
    static let pidFileName = "git.pid"

    /// Gives the arguments of a git alias that writes the process id of git to a file, and then runs for
    /// ``slowCommandDuration``.
    ///
    /// The alias runs in a shell whose parent process is git, so `$PPID` in the shell is the process id of git.
    ///
    /// - Parameter file: The file that gets the process id.
    /// - Returns: The arguments after `git`.
    static func slowArguments(recordingPIDIn file: URL) -> [String] {
        let seconds = slowCommandDuration.components.seconds
        return ["-c", "alias.slowchild=!echo $PPID > '\(file.path)'; sleep \(seconds)", "slowchild"]
    }

    /// Reads the process id that the slow command wrote.
    ///
    /// - Parameter file: The file of the process id.
    /// - Returns: The process id, or `nil` when the file does not hold a process id yet.
    static func recordedPID(in file: URL) -> pid_t? {
        FileManager.default.contents(atPath: file.path).flatMap { bytes in
            pid_t(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Tells if a process ended and its parent collected its exit status, so no process has the id.
    ///
    /// - Parameter pid: The process id.
    /// - Returns: `true` when no process has the id.
    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    /// Runs one git command ``parallelCommandCount`` times, all at the same time, and runs a body while the
    /// commands run.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - limit: The time limit of each command.
    ///   - body: The work that runs while the commands run.
    /// - Returns: The value of the body, and the exit status of each command.
    /// - Throws: A ``BoardKeyError`` when a command cannot start or does not end, or the error of the body.
    static func runningGitInParallel<Value: Sendable>(
        withArguments arguments: [String],
        inDirectory directory: URL,
        timeLimit limit: Duration,
        while body: () async throws -> Value
    ) async throws -> (value: Value, statuses: [Int32]) {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<parallelCommandCount {
                group.addTask {
                    try await Git.run(withArguments: arguments, inDirectory: directory, timeLimit: limit).status
                }
            }
            let value = try await body()
            let statuses = try await group.reduce(into: []) { statuses, status in statuses.append(status) }
            return (value, statuses)
        }
    }

    @Test("A large standard error of git does not block the read of the standard output")
    func largeErrorOutputDoesNotBlock() async throws {
        let sandbox = try GitSandbox()
        let result = try await Git.run(withArguments: Self.floodArguments, inDirectory: sandbox.root)
        #expect(result.status == Git.successStatus)
        #expect(result.output == "\(Self.floodWord)\n")
        #expect(result.errorOutput.utf8.count == Self.floodSize)
    }

    @Test("A git command that runs longer than its time limit stops with a time-out error")
    func slowCommandTimesOut() async throws {
        let sandbox = try GitSandbox()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: BoardKeyError.gitTimedOut(arguments: Self.slowArguments)) {
            try await Git.run(
                withArguments: Self.slowArguments,
                inDirectory: sandbox.root,
                timeLimit: Self.shortGitLimit
            )
        }
        #expect(start.duration(to: clock.now) < Self.slowCommandDuration)
    }

    @Test("Git commands in more tasks than processors all end")
    func parallelCommandsAllEnd() async throws {
        let sandbox = try GitSandbox()
        let (_, statuses) = try await Self.runningGitInParallel(
            withArguments: Self.versionArguments,
            inDirectory: sandbox.root,
            timeLimit: Git.defaultTimeLimit
        ) {}
        #expect(statuses == Array(repeating: Git.successStatus, count: Self.parallelCommandCount))
    }

    @Test("A short sleep wakes near its deadline while many slow git commands run")
    func sleepWakesWhileGitRuns() async throws {
        let sandbox = try GitSandbox()
        let clock = ContinuousClock()
        let (waited, statuses) = try await Self.runningGitInParallel(
            withArguments: Self.slowArguments,
            inDirectory: sandbox.root,
            timeLimit: Git.defaultTimeLimit
        ) {
            let start = clock.now
            try await Task.sleep(for: Self.shortSleep)
            return start.duration(to: clock.now)
        }
        #expect(waited < Self.slowCommandDuration, "The sleep must not wait for the end of a git command")
        #expect(statuses == Array(repeating: Git.successStatus, count: Self.parallelCommandCount))
    }

    @Test("A cancelled git command ends at once, and its git process is gone")
    func cancelledCommandStopsGit() async throws {
        let sandbox = try GitSandbox()
        let directory = sandbox.root
        let pidFile = directory.appending(path: Self.pidFileName)
        let arguments = Self.slowArguments(recordingPIDIn: pidFile)
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await withThrowingTaskGroup(of: Result<Git.Output, BoardKeyError>.self) { group in
            group.addTask {
                do throws(BoardKeyError) {
                    return .success(try await Git.run(withArguments: arguments, inDirectory: directory))
                } catch {
                    return .failure(error)
                }
            }
            try await EventLogTests.waitUntil { Self.recordedPID(in: pidFile) != nil }
            group.cancelAll()
            return try await group.next()
        }
        #expect(start.duration(to: clock.now) < Self.slowCommandDuration)
        let result = try #require(outcome)
        #expect(throws: BoardKeyError.gitCancelled(arguments: arguments)) { try result.get() }
        let pid = try #require(Self.recordedPID(in: pidFile))
        try await EventLogTests.waitUntil { Self.isGone(pid) }
    }
}

// MARK: - Temporary repos

/// A temporary directory that holds the git repos of one test. The directory is removed when the sandbox ends.
///
/// The sandbox is a class, because its `deinit` removes the directory.
final class GitSandbox {
    /// The name of the author of each commit that the sandbox makes.
    static let userName = "Board Key Tests"

    /// The email of the author of each commit that the sandbox makes.
    static let userEmail = "tests@example.invalid"

    /// The message of the one commit of each repo that ``makeRepo(named:origin:)`` makes.
    static let startCommitMessage = "Start"

    /// The local config of a repo that ``initializeRepo(at:withIdentity:)`` makes with an identity: the name and
    /// the email of the author, and no commit signatures, because the setup has no signing key.
    static let identityConfig = [
        ("user.name", userName),
        ("user.email", userEmail),
        ("commit.gpgsign", "false"),
    ]

    /// The time of each commit of ``commit(message:in:)`` and ``merge(_:in:)``. All commits have the same time, so
    /// `git rev-list` lists the parents of a merge in the order of the merge.
    static let fixedCommitDate = "2026-01-01T00:00:00Z"

    /// The variables that give each commit the time ``fixedCommitDate``.
    static let fixedDateVariables = ["GIT_AUTHOR_DATE": fixedCommitDate, "GIT_COMMITTER_DATE": fixedCommitDate]

    /// The name of the home folder of git in the environment of ``makeEnvironmentWithoutIdentity()``.
    static let homeFolderName = "home"

    /// The name of the global git config file in the home folder of ``makeEnvironmentWithoutIdentity()``.
    static let globalConfigFileName = ".gitconfig"

    /// The global git config of ``makeEnvironmentWithoutIdentity()``. Git uses only the identity of its config, and
    /// does not make an identity from the name of the user and of the host.
    static let configOnlyIdentityText = "[user]\n\tuseConfigOnly = true\n"

    /// The prefix of the names of the environment variables of git. ``makeEnvironmentWithoutIdentity()`` removes
    /// each one, for example `GIT_AUTHOR_NAME`.
    static let gitVariablePrefix = "GIT_"

    /// The environment variable that git reads as the email of a commit when the config has none.
    static let emailVariable = "EMAIL"

    /// The temporary directory of the sandbox.
    let root: URL

    /// Makes an empty temporary directory in the folder of the ``TestFolderGroup/gitSandboxes`` group of the run folder
    /// of ``TestFolderRoot``.
    ///
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    init() throws {
        let name = "BoardKeyTests-\(UUID().uuidString)"
        root = try TestFolderRoot.folder(of: .gitSandboxes).appending(path: name, directoryHint: .isDirectory)
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
    func makeRepo(named name: String, origin: String? = nil) async throws -> URL {
        let repo = try await makeEmptyRepo(named: name)
        let commitArguments = ["commit", "--quiet", "--allow-empty", "-m", Self.startCommitMessage]
        try await Self.runGit(withArguments: commitArguments, in: repo)
        if let origin {
            try await Self.runGit(withArguments: ["remote", "add", "origin", origin], in: repo)
        }
        return repo
    }

    /// Makes an empty folder in a folder. The new folder is not a git repo.
    ///
    /// - Parameters:
    ///   - name: The name of the new folder.
    ///   - parent: The folder that holds the new folder.
    /// - Returns: The new folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    static func makeFolder(named name: String, in parent: URL) throws -> URL {
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Adds a worktree of a repo in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the worktree directory. It is also the name of the new branch.
    ///   - repo: The main clone.
    /// - Returns: The worktree directory.
    /// - Throws: An error when the git command cannot start or fails.
    func addWorktree(named name: String, to repo: URL) async throws -> URL {
        let worktree = root.appending(path: name, directoryHint: .isDirectory)
        try await Self.runGit(withArguments: ["worktree", "add", "--quiet", "-b", name, worktree.path], in: repo)
        return worktree
    }

    /// Runs a git command in a directory, and requires that it succeeds.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    /// - Throws: A ``BoardKeyError`` when git cannot start. An `ExpectationFailedError` when git exits with a failure
    ///   status.
    static func runGit(withArguments arguments: [String], in directory: URL) async throws {
        _ = try await output(ofGit: arguments, in: directory)
    }

    /// Runs a git command in a directory, requires that it succeeds, and gives its output.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - environment: The environment of git, or `nil` for the environment of the test process.
    /// - Returns: The standard output of git, with no white space at the start and at the end.
    /// - Throws: A ``BoardKeyError`` when git cannot start. An `ExpectationFailedError` when git exits with a failure
    ///   status.
    static func output(
        ofGit arguments: [String],
        in directory: URL,
        environment: [String: String]? = nil
    ) async throws -> String {
        let result = try await Git.run(withArguments: arguments, inDirectory: directory, environment: environment)
        try #require(result.status == Git.successStatus, "git \(arguments) failed: \(result.errorOutput)")
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes a git repo with no commit in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - hasIdentity: `true` puts ``identityConfig`` in the config of the repo, so git can make a commit with no
    ///     global config. `false` gives a repo with no config of its own.
    /// - Returns: The repo directory.
    /// - Throws: An error when the directory cannot be made, or when a git command cannot start or fails.
    func makeEmptyRepo(named name: String, withIdentity hasIdentity: Bool = true) async throws -> URL {
        let repo = try Self.makeFolder(named: name, in: root)
        try await Self.initializeRepo(at: repo, withIdentity: hasIdentity)
        return repo
    }

    /// Runs `git init` in a folder, and puts the git identity in the config of the new repo. The repo has no commit.
    ///
    /// - Parameters:
    ///   - folder: The folder that becomes the repo. The folder must exist.
    ///   - hasIdentity: `true` puts ``identityConfig`` in the config of the repo, so git can make a commit with no
    ///     global config. `false` gives a repo with no config of its own.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    static func initializeRepo(at folder: URL, withIdentity hasIdentity: Bool = true) async throws {
        try await runGit(withArguments: ["init", "--quiet"], in: folder)
        for (key, value) in identityConfig where hasIdentity {
            try await runGit(withArguments: ["config", key, value], in: folder)
        }
    }

    /// Makes an empty commit on the current branch of a repo, at ``fixedCommitDate``.
    ///
    /// - Parameters:
    ///   - message: The message of the commit.
    ///   - repo: The repo directory. Its config has ``identityConfig``.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func commit(message: String, in repo: URL) async throws {
        let arguments = ["commit", "--quiet", "--allow-empty", "-m", message]
        _ = try await Self.output(ofGit: arguments, in: repo, environment: Self.fixedDateEnvironment)
    }

    /// Merges a branch with an unrelated history into the current branch of a repo, at ``fixedCommitDate``.
    ///
    /// - Parameters:
    ///   - branch: The branch to merge.
    ///   - repo: The repo directory. Its config has ``identityConfig``.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func merge(_ branch: String, in repo: URL) async throws {
        let arguments = ["merge", "--quiet", "--no-edit", "--allow-unrelated-histories", branch]
        _ = try await Self.output(ofGit: arguments, in: repo, environment: Self.fixedDateEnvironment)
    }

    /// The environment of the test process, with the commit time ``fixedCommitDate``.
    static var fixedDateEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.merging(fixedDateVariables) { _, fixed in fixed }
    }

    /// Clones a repo into the sandbox. The `origin` of the clone is the path of the repo, which has no host.
    ///
    /// - Parameters:
    ///   - repo: The repo to clone.
    ///   - name: The name of the directory of the clone.
    /// - Returns: The directory of the clone.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func cloneRepo(_ repo: URL, named name: String) async throws -> URL {
        let clone = root.appending(path: name, directoryHint: .isDirectory)
        try await Self.runGit(withArguments: ["clone", "--quiet", repo.path, clone.path], in: root)
        return clone
    }

    /// Gives the root commit key of a repo whose `HEAD` commit is its one root commit.
    ///
    /// - Parameter repo: The repo directory.
    /// - Returns: The key `local/<first 12 hex digits of HEAD>`.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func headKey(of repo: URL) async throws -> BoardKey {
        BoardKey(rootCommit: try await Self.headSHA(of: repo))
    }

    /// Gives the SHA of the `HEAD` commit of a repo.
    ///
    /// - Parameter repo: The repo directory.
    /// - Returns: The full SHA of the commit that `HEAD` names.
    /// - Throws: A ``BoardKeyError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    static func headSHA(of repo: URL) async throws -> String {
        try await output(ofGit: ["rev-parse", "HEAD"], in: repo)
    }

    /// Makes an environment where git has no identity: the home folder and the global config are in the sandbox,
    /// git reads no system config, and no environment variable gives a name or an email.
    ///
    /// - Returns: The environment of git.
    /// - Throws: An error from `FileManager` when the home folder or the config file cannot be made.
    func makeEnvironmentWithoutIdentity() throws -> [String: String] {
        let home = try Self.makeFolder(named: Self.homeFolderName, in: root)
        let config = home.appending(path: Self.globalConfigFileName)
        try Self.configOnlyIdentityText.write(to: config, atomically: true, encoding: .utf8)
        let inherited = ProcessInfo.processInfo.environment.filter { name, _ in
            !name.hasPrefix(Self.gitVariablePrefix) && name != Self.emailVariable
        }
        let isolated = ["HOME": home.path, "GIT_CONFIG_GLOBAL": config.path, "GIT_CONFIG_NOSYSTEM": "1"]
        return inherited.merging(isolated) { _, isolatedValue in isolatedValue }
    }
}
