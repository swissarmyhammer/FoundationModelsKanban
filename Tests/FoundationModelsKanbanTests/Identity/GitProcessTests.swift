import Foundation
import Testing

/// Tests the run of the `git` program of the tests (``GitProcess``). The tests make their repos with it, and many
/// tests run at the same time.
@Suite("Git process of the tests")
struct GitProcessTests {

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
    /// - Throws: A ``GitProcessError`` when a command cannot start or does not end, or the error of the body.
    static func runningGitInParallel<Value: Sendable>(
        withArguments arguments: [String],
        inDirectory directory: URL,
        timeLimit limit: Duration,
        while body: () async throws -> Value
    ) async throws -> (value: Value, statuses: [Int32]) {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<parallelCommandCount {
                group.addTask {
                    try await GitProcess.run(withArguments: arguments, inDirectory: directory, timeLimit: limit).status
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
        let result = try await GitProcess.run(withArguments: Self.floodArguments, inDirectory: sandbox.root)
        #expect(result.status == GitProcess.successStatus)
        #expect(result.output == "\(Self.floodWord)\n")
        #expect(result.errorOutput.utf8.count == Self.floodSize)
    }

    @Test("A git command that runs longer than its time limit stops with a time-out error")
    func slowCommandTimesOut() async throws {
        let sandbox = try GitSandbox()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: GitProcessError.timedOut(arguments: Self.slowArguments)) {
            try await GitProcess.run(
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
            timeLimit: GitProcess.defaultTimeLimit
        ) {}
        #expect(statuses == Array(repeating: GitProcess.successStatus, count: Self.parallelCommandCount))
    }

    @Test("A short sleep wakes near its deadline while many slow git commands run")
    func sleepWakesWhileGitRuns() async throws {
        let sandbox = try GitSandbox()
        let clock = ContinuousClock()
        let (waited, statuses) = try await Self.runningGitInParallel(
            withArguments: Self.slowArguments,
            inDirectory: sandbox.root,
            timeLimit: GitProcess.defaultTimeLimit
        ) {
            let start = clock.now
            try await Task.sleep(for: Self.shortSleep)
            return start.duration(to: clock.now)
        }
        #expect(waited < Self.slowCommandDuration, "The sleep must not wait for the end of a git command")
        #expect(statuses == Array(repeating: GitProcess.successStatus, count: Self.parallelCommandCount))
    }

    @Test("A cancelled git command ends at once, and its git process is gone")
    func cancelledCommandStopsGit() async throws {
        let sandbox = try GitSandbox()
        let directory = sandbox.root
        let pidFile = directory.appending(path: Self.pidFileName)
        let arguments = Self.slowArguments(recordingPIDIn: pidFile)
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await withThrowingTaskGroup(of: Result<GitProcess.Output, GitProcessError>.self) { group in
            group.addTask {
                do throws(GitProcessError) {
                    return .success(try await GitProcess.run(withArguments: arguments, inDirectory: directory))
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
        #expect(throws: GitProcessError.cancelled(arguments: arguments)) { try result.get() }
        let pid = try #require(Self.recordedPID(in: pidFile))
        try await EventLogTests.waitUntil { Self.isGone(pid) }
    }
}
