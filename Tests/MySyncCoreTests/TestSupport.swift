import Foundation
@testable import MySyncCore

enum TestCalendar {
    static var berlin: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal
    }

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
}

final class FakeRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    var versionOutput = "openrsync: protocol version 29"
    var result = ProcessResult(exitCode: 0)
    var error: Error?
    private(set) var calls: [(String, [String])] = []

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        lock.withLock { calls.append((executable, arguments)) }
        if arguments == ["--version"] { return ProcessResult(exitCode: 0, stdout: versionOutput) }
        if let error { throw error }
        return result
    }

    var syncCalls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return calls.map(\.1).filter { $0 != ["--version"] }
    }
}

struct FakeReachability: ReachabilityChecking {
    var reachable: Bool
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool { reachable }
}

struct FakeNetwork: NetworkInfoProviding {
    var snap: NetworkSnapshot
    func snapshot() -> NetworkSnapshot { snap }
}

final class FakeEngine: SyncPerforming, @unchecked Sendable {
    private let lock = NSLock()
    var results: [UUID: SyncResult] = [:]
    var defaultResult = SyncResult(outcome: .success)
    var delayNanoseconds: UInt64 = 0
    private(set) var performed: [UUID] = []

    func perform(job: SyncJob, computer: Computer, settings: AppSettings) async -> SyncResult {
        let r = lock.withLock { () -> SyncResult in performed.append(job.id); return results[job.id] ?? defaultResult }
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        return r
    }

    var performedJobs: [UUID] { lock.lock(); defer { lock.unlock() }; return performed }
}

final class RecordingNotifier: Notifying, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var messages: [(title: String, body: String)] = []
    func notify(title: String, body: String) {
        lock.lock(); messages.append((title, body)); lock.unlock()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return messages.count }
}

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

func makeComputer(ssids: [String] = [], subnets: [String] = []) -> Computer {
    Computer(name: "NAS", host: "nas.local", user: "rene", port: 22, ssids: ssids, subnets: subnets)
}

func makeJob(computer: Computer, schedule: Schedule = .hourly, direction: SyncDirection = .push) -> SyncJob {
    SyncJob(computerID: computer.id, localPath: "/Users/test/Fotos", remotePath: "/volume1/Fotos",
            direction: direction, schedule: schedule)
}
