import Foundation
import Synchronization

// MARK: - Errors

/// An error of a run of the `git` program in a test.
enum GitProcessError: Error, Hashable, Sendable {
    /// The `git` program did not start, for example because git is not installed or the directory does not exist.
    case unavailable(message: String)

    /// A `git` command did not end in its time limit, so it was stopped.
    case timedOut(arguments: [String])

    /// The task that waited for a `git` command was cancelled, so the command was stopped.
    case cancelled(arguments: [String])
}

// MARK: - Git process

/// Runs the `git` command-line tool in a test. The tests make their repos with it. The package code never runs it: the
/// package reads git with libgit2 in the process (``BoardRepo``).
enum GitProcess {
    /// The exit status of a git command that succeeded.
    static let successStatus: Int32 = 0

    /// The program that finds `git` on the `PATH`.
    static let launcherPath = "/usr/bin/env"

    /// The name of the git program, which ``launcherPath`` finds.
    static let programName = "git"

    /// The number of seconds in ``defaultTimeLimit``.
    private static let defaultTimeLimitSeconds = 30

    /// The longest time that a git command can run before it is stopped. A local git command ends in much less time.
    static let defaultTimeLimit = Duration.seconds(defaultTimeLimitSeconds)

    /// The result of a git command.
    struct Output: Sendable {
        /// The exit status.
        let status: Int32

        /// The standard output, as UTF-8 text.
        let output: String

        /// The standard error, as UTF-8 text.
        let errorOutput: String
    }

    /// Runs git in a directory, and waits until it exits, until its time limit ends, or until the task is cancelled.
    ///
    /// The wait blocks no thread: the exit of git and the ends of its two pipes resume the caller. Thus many calls at
    /// the same time do not take the threads of Swift concurrency from other tasks. Git gets an empty standard input,
    /// so it never waits for input. The standard output and the standard error are read at the same time, so a large
    /// output on one pipe cannot stop git while the run waits for the other pipe. When the time limit ends or the task
    /// is cancelled, the run stops git and returns at once. It does not wait for the pipes then, because a child of
    /// git (for example the shell of an alias) can keep them open.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - environment: The environment of git, or `nil` for the environment of the process.
    ///   - limit: The longest time that git can run. When this time ends, git is stopped.
    /// - Returns: The exit status and the output of git.
    /// - Throws: ``GitProcessError/unavailable(message:)`` when git cannot start.
    ///   ``GitProcessError/timedOut(arguments:)`` when git does not end in the time limit.
    ///   ``GitProcessError/cancelled(arguments:)`` when the task is cancelled before git ends.
    static func run(
        withArguments arguments: [String],
        inDirectory directory: URL,
        environment: [String: String]? = nil,
        timeLimit limit: Duration = defaultTimeLimit
    ) async throws(GitProcessError) -> Output {
        let record = GitRecord()
        let process = makeProcess(withArguments: arguments, inDirectory: directory, recordingTo: record)
        process.environment = environment
        async let _ = record.stop(process, after: limit, with: .timedOut(arguments: arguments))
        let outcome = await withTaskCancellationHandler {
            await record.outcome(ofStarting: process)
        } onCancel: {
            record.stop(process, with: .cancelled(arguments: arguments))
        }
        return try outcome.get()
    }

    /// Makes the git process, and connects its exit and its two pipes to a record.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - record: The record that gets the exit status and the bytes of the two pipes.
    /// - Returns: The process, not started.
    private static func makeProcess(
        withArguments arguments: [String],
        inDirectory directory: URL,
        recordingTo record: GitRecord
    ) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = [programName] + arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = record.makePipe(for: .output)
        process.standardError = record.makePipe(for: .errorOutput)
        process.terminationHandler = { ended in record.recordExit(withStatus: ended.terminationStatus) }
        return process
    }
}

/// One of the two output streams of a git process.
private enum GitStream {
    /// The standard output.
    case output

    /// The standard error.
    case errorOutput
}

/// The bytes of one output stream of a git process.
private struct StreamBytes {
    /// The bytes that the pipe gave until now.
    private var data = Data()

    /// `true` after the pipe ended.
    private(set) var isEnded = false

    /// The bytes as UTF-8 text.
    var text: String {
        String(decoding: data, as: UTF8.self)
    }

    /// Adds one chunk of the pipe. An empty chunk is the end of the pipe.
    ///
    /// - Parameter chunk: The bytes that the pipe gave.
    mutating func add(_ chunk: Data) {
        if chunk.isEmpty {
            isEnded = true
        } else {
            data.append(chunk)
        }
    }
}

/// The state of one git run.
private struct GitRunState {
    /// The phase of the git process.
    enum Phase {
        /// The process did not start.
        case notStarted

        /// The process runs.
        case running

        /// The process exited with a status.
        case exited(status: Int32)
    }

    /// The phase of the git process.
    var phase = Phase.notStarted

    /// The bytes of the standard output.
    var output = StreamBytes()

    /// The bytes of the standard error.
    var errorOutput = StreamBytes()

    /// The result of the run, or `nil` until git and its pipes end or the run stops. The first result stays.
    var outcome: GitRecord.Outcome?

    /// The caller that waits for the result, or `nil` before the wait and after the resume.
    var waiter: GitRecord.Waiter?

    /// Adds one chunk to the bytes of a stream.
    ///
    /// - Parameters:
    ///   - chunk: The bytes that the pipe gave. An empty chunk is the end of the pipe.
    ///   - stream: The stream of the pipe.
    mutating func add(_ chunk: Data, to stream: GitStream) {
        switch stream {
        case .output: output.add(chunk)
        case .errorOutput: errorOutput.add(chunk)
        }
    }

    /// Starts git, unless the run stopped before the start.
    ///
    /// - Parameter process: The git process.
    mutating func start(_ process: Process) {
        guard outcome == nil else {
            return
        }
        do {
            try process.run()
            phase = .running
        } catch {
            outcome = .failure(.unavailable(message: error.localizedDescription))
        }
    }

    /// Ends the run with an error, unless the run has a result already.
    ///
    /// - Parameter error: The error of the run.
    /// - Returns: `true` when git runs, so the caller must stop git.
    mutating func stop(with error: GitProcessError) -> Bool {
        guard outcome == nil else {
            return false
        }
        outcome = .failure(error)
        guard case .running = phase else {
            return false
        }
        return true
    }

    /// Records the result when git exited and both pipes ended, unless the run has a result already.
    mutating func settle() {
        guard outcome == nil, case .exited(let status) = phase, output.isEnded, errorOutput.isEnded else {
            return
        }
        outcome = .success(GitProcess.Output(status: status, output: output.text, errorOutput: errorOutput.text))
    }

    /// Takes the caller and the result when both are there, so that the caller is resumed one time only.
    ///
    /// - Returns: The caller and the result, or `nil` when one of them is not there.
    mutating func takeReadyWaiter() -> (waiter: GitRecord.Waiter, outcome: GitRecord.Outcome)? {
        guard let waiter, let outcome else {
            return nil
        }
        self.waiter = nil
        return (waiter, outcome)
    }
}

/// Collects the parts of the result of one git run, and resumes the caller that waits for the result.
///
/// The run blocks no thread. The termination handler of the process and the readability handlers of the two pipes
/// record their parts. The caller waits in a checked continuation, which the record resumes one time: when git exited
/// and both pipes ended, or at once when the run stops.
///
/// A `Mutex` guards the state, and not an actor: the handlers of Foundation and the cancel handler are synchronous, so
/// each must record its part at once, with no `await`. The record holds no reference to the process, so the handlers
/// that the process holds make no reference cycle.
private final class GitRecord: Sendable {
    /// The result of a run: the output of git, or the error of the run.
    typealias Outcome = Result<GitProcess.Output, GitProcessError>

    /// The caller that waits for the result of a run.
    typealias Waiter = CheckedContinuation<Outcome, Never>

    /// The state of the run.
    private let state = Mutex(GitRunState())

    /// Makes a pipe whose readability handler records each chunk of one stream of git.
    ///
    /// - Parameter stream: The stream that the pipe carries.
    /// - Returns: The pipe.
    func makePipe(for stream: GitStream) -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in self.read(from: handle, into: stream) }
        return pipe
    }

    /// Reads the data that a pipe has now. At the end of the pipe, the read also removes the readability handler.
    ///
    /// - Parameters:
    ///   - handle: The read end of the pipe.
    ///   - stream: The stream that the pipe carries.
    private func read(from handle: FileHandle, into stream: GitStream) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
        }
        update { state in state.add(chunk, to: stream) }
    }

    /// Records the exit of git.
    ///
    /// - Parameter status: The exit status of git.
    func recordExit(withStatus status: Int32) {
        update { state in state.phase = .exited(status: status) }
    }

    /// Starts git, and waits for the result of the run. The wait blocks no thread.
    ///
    /// - Parameter process: The git process.
    /// - Returns: The result of the run.
    func outcome(ofStarting process: Process) async -> Outcome {
        await withCheckedContinuation { waiter in
            update { state in
                state.waiter = waiter
                state.start(process)
            }
        }
    }

    /// Ends the run with an error, and stops git when it runs. A run that has a result already does not change.
    ///
    /// - Parameters:
    ///   - process: The git process.
    ///   - error: The error of the run.
    func stop(_ process: Process, with error: GitProcessError) {
        if update({ state in state.stop(with: error) }) {
            process.terminate()
        }
    }

    /// Waits for a time limit, and then ends the run with an error.
    ///
    /// The cancel of the task of the wait ends the wait with no stop. The task is cancelled when the run ended first,
    /// or when the caller was cancelled: the cancel handler of the caller then stops the run.
    ///
    /// - Parameters:
    ///   - process: The git process.
    ///   - limit: The time limit.
    ///   - error: The error of the run when the time limit ends.
    func stop(_ process: Process, after limit: Duration, with error: GitProcessError) async {
        do {
            try await Task.sleep(for: limit)
        } catch {
            // `Task.sleep` throws only `CancellationError`, so the run ended or the cancel handler stops it.
            return
        }
        stop(process, with: error)
    }

    /// Changes the state under the lock, records the result when it is complete, and then resumes the waiting
    /// caller when the result is there.
    ///
    /// - Parameter change: The change of the state.
    /// - Returns: The value of the change.
    @discardableResult
    private func update<Value: Sendable>(_ change: (inout GitRunState) -> Value) -> Value {
        let (value, ready) = state.withLock { state in
            let value = change(&state)
            state.settle()
            return (value, state.takeReadyWaiter())
        }
        if let ready {
            ready.waiter.resume(returning: ready.outcome)
        }
        return value
    }
}
