import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

/// Startet echte Prozesse über `Process`.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Ausgaben laufend einsammeln, damit volle Pipes den Prozess nicht blockieren.
        let collector = OutputCollector()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendOut(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendErr(handle.availableData)
        }

        let timeoutFlag = TimeoutFlag()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: collector.out,
                    stderr: collector.err,
                    timedOut: timeoutFlag.value
                ))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
                return
            }
            if timeout > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        timeoutFlag.set()
                        process.terminate()
                    }
                }
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()

    func appendOut(_ d: Data) { lock.lock(); outData.append(d); lock.unlock() }
    func appendErr(_ d: Data) { lock.lock(); errData.append(d); lock.unlock() }
    var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
    var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
