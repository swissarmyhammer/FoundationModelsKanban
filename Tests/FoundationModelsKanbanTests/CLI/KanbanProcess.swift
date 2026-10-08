import Foundation
import Testing

/// One run of the built `kanban` executable as a child process (plan.md §7.2).
///
/// The executable is in the build products directory, next to the test bundle. A plain `swift test` builds it,
/// because SwiftPM builds each product of the package before it runs the tests.
///
/// The child gets an empty standard input. A readability handler empties each of the standard output and the standard
/// error on its own queue as soon as data comes, so a full pipe never stops the child. Each wait of the test reads an
/// async stream through ``StreamWait``, so no wait blocks past its time limit. The run ends the child when the value
/// ends, so a test never leaves a child that runs.
///
/// The type is a class, because its `deinit` ends the child.
final class KanbanProcess {
    /// How a child process ended: the reason and the status.
    struct Exit: Equatable, Sendable {
        /// The exit of a run that succeeded: a normal exit with the status `EXIT_SUCCESS`.
        static let success = Exit(reason: .exit, status: EXIT_SUCCESS)

        /// A normal exit, or the end by a signal.
        let reason: Process.TerminationReason

        /// The exit status of a normal exit, or the number of the signal.
        let status: Int32
    }

    /// The result of a run that ended.
    struct Result: Sendable {
        /// How the child ended.
        let exit: Exit

        /// The standard output, as UTF-8 text.
        let output: String

        /// The standard error, as UTF-8 text.
        let errorOutput: String
    }

    /// The name of the executable product.
    private static let executableName = "kanban"

    /// The byte at the end of each line of the standard output.
    private static let newline = UInt8(ascii: "\n")

    /// The child process.
    private let process = Process()

    /// The chunks of the standard output, in order. The stream ends when the child closes its standard output.
    private let output: AsyncStream<Data>

    /// The chunks of the standard error, in order. The stream ends when the child closes its standard error.
    private let errorOutput: AsyncStream<Data>

    /// The one exit of the child. The stream ends after it.
    private let exit: AsyncStream<Exit>

    /// Starts the executable in a directory.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `kanban`.
    ///   - directory: The current directory of the child.
    /// - Throws: An error from `Process` when the executable cannot start.
    init(withArguments arguments: [String], inDirectory directory: URL) throws {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let (exitStream, exitContinuation) = AsyncStream.makeStream(of: Exit.self)
        output = Self.chunks(of: outputPipe)
        errorOutput = Self.chunks(of: errorPipe)
        exit = exitStream
        process.executableURL = try Self.executableURL()
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { ended in
            exitContinuation.yield(Exit(reason: ended.terminationReason, status: ended.terminationStatus))
            exitContinuation.finish()
        }
        try process.run()
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Finds the executable next to the bundle of the tests.
    ///
    /// - Returns: The URL of the executable.
    /// - Throws: An `ExpectationFailedError` when the build products directory has no executable.
    private static func executableURL() throws -> URL {
        let products = Bundle(for: KanbanProcess.self).bundleURL.deletingLastPathComponent()
        let executable = products.appending(path: executableName, directoryHint: .notDirectory)
        try #require(FileManager.default.isExecutableFile(atPath: executable.path), "no \(executable.path)")
        return executable
    }

    /// Starts to empty a pipe, and gives its chunks as a stream.
    ///
    /// - Parameter pipe: The pipe. The stream ends when the last writer closes it.
    /// - Returns: The chunks of the pipe, in order.
    private static func chunks(of pipe: Pipe) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            forward(handle.availableData, from: handle, to: continuation)
        }
        return stream
    }

    /// Gives one chunk of a pipe to its stream. An empty chunk is the end of the pipe: it ends the stream and the
    /// reads of the pipe.
    ///
    /// - Parameters:
    ///   - chunk: The data that the pipe gave.
    ///   - handle: The read end of the pipe.
    ///   - continuation: The continuation of the stream of the pipe.
    private static func forward(
        _ chunk: Data,
        from handle: FileHandle,
        to continuation: AsyncStream<Data>.Continuation
    ) {
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            continuation.finish()
            return
        }
        continuation.yield(chunk)
    }

    /// Joins the chunks of a stream until the stream ends.
    ///
    /// - Parameter chunks: The chunks.
    /// - Returns: The bytes as UTF-8 text.
    private static func text(of chunks: AsyncStream<Data>) async -> String {
        let bytes = await chunks.reduce(into: Data()) { bytes, chunk in bytes.append(chunk) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Reads the chunks of a stream until the first end of line.
    ///
    /// - Parameter chunks: The chunks of the standard output.
    /// - Returns: The first line without its end of line, or `nil` when the stream ends before an end of line.
    private static func firstLine(of chunks: AsyncStream<Data>) async -> String? {
        var bytes = Data()
        for await chunk in chunks {
            bytes.append(chunk)
            if let end = bytes.firstIndex(of: newline) {
                return String(decoding: bytes[..<end], as: UTF8.self)
            }
        }
        return nil
    }

    /// Waits until the child ends, and gives its result.
    ///
    /// - Returns: The exit and the output of the child. The output does not have the text that ``firstLine()``
    ///   read before.
    /// - Throws: An `ExpectationFailedError` when the child does not end in the time limit of ``StreamWait``.
    func result() async throws -> Result {
        let output = output
        let errorOutput = errorOutput
        let exit = exit
        let result = try await StreamWait.value {
            async let outputText = Self.text(of: output)
            async let errorText = Self.text(of: errorOutput)
            var exits = exit.makeAsyncIterator()
            let ended = await exits.next()
            return (ended, await outputText, await errorText)
        }
        let (ended, outputText, errorText) = try #require(result, "kanban did not end in the time limit")
        return Result(exit: try #require(ended), output: outputText, errorOutput: errorText)
    }

    /// Waits for the first line of the standard output.
    ///
    /// - Returns: The line without its end of line, or `nil` when the output ends or the time limit ends first.
    /// - Throws: An error from the wait.
    func firstLine() async throws -> String? {
        let output = output
        let line = try await StreamWait.value {
            await Self.firstLine(of: output)
        }
        return line ?? nil
    }

    /// Sends SIGINT to the child, as a person who stops the child with Control-C.
    func interrupt() {
        process.interrupt()
    }
}
