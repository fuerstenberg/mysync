import XCTest
@testable import MySyncCore

/// Tests mit echten Prozessen.
final class ProcessRunnerTests: XCTestCase {
    let runner = ProcessRunner()

    func testCapturesStdout() async throws {
        let r = try await runner.run(executable: "/bin/echo", arguments: ["hallo"], timeout: 5)
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.stdout, "hallo\n")
    }

    func testCapturesExitCodeAndStderr() async throws {
        let r = try await runner.run(executable: "/bin/sh", arguments: ["-c", "echo kaputt >&2; exit 3"], timeout: 5)
        XCTAssertEqual(r.exitCode, 3)
        XCTAssertEqual(r.stderr, "kaputt\n")
        XCTAssertFalse(r.succeeded)
    }

    func testTimeout() async throws {
        let start = Date()
        let r = try await runner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.5)
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testLargeOutputDoesNotBlock() async throws {
        let r = try await runner.run(executable: "/bin/sh", arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' 'a'"], timeout: 10)
        XCTAssertEqual(r.stdout.count, 300_000)
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await runner.run(executable: "/gibt/es/nicht", arguments: [], timeout: 1)
            XCTFail("Fehler erwartet")
        } catch {}
    }
}

final class RsyncIntegrationTests: XCTestCase {
    var root: URL!
    var source: URL!
    var dest: URL!

    override func setUpWithError() throws {
        guard RsyncLocator.locate(customPath: "") != nil else { throw XCTSkip("rsync nicht installiert") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mysync-rsync-\(UUID().uuidString)")
        source = root.appendingPathComponent("Quelle mit Leerzeichen")
        dest = root.appendingPathComponent("Ziel")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("unter"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("eins".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("zwei".utf8).write(to: source.appendingPathComponent("unter/b.txt"))
        try Data("weg".utf8).write(to: source.appendingPathComponent(".DS_Store"))
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func run(_ job: SyncJob) async throws -> ProcessResult {
        let rsync = RsyncLocator.locate(customPath: "")!
        let args = RsyncCommandBuilder().localArguments(for: job, destination: dest.path)
        return try await ProcessRunner().run(executable: rsync, arguments: args, timeout: 30)
    }

    func job(delete: Bool = false) -> SyncJob {
        SyncJob(computerID: UUID(), localPath: source.path, remotePath: "", direction: .push, deleteExtraneous: delete)
    }

    func testCopiesContentWithoutExtraFolder() async throws {
        let r = try await run(job())
        XCTAssertTrue(r.succeeded, r.stderr)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8), "eins")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("unter/b.txt"), encoding: .utf8), "zwei")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".DS_Store").path), "Ausschluss greift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("Quelle mit Leerzeichen").path))
    }

    func testDeleteRemovesExtraneousFiles() async throws {
        try Data("alt".utf8).write(to: dest.appendingPathComponent("alt.txt"))
        _ = try await run(job(delete: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("alt.txt").path))
        let r = try await run(job(delete: true))
        XCTAssertTrue(r.succeeded, r.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("alt.txt").path))
    }

    func testPullDirection() async throws {
        try Data("vom server".utf8).write(to: dest.appendingPathComponent("remote.txt"))
        var j = job()
        j.direction = .pull
        let r = try await run(j)
        XCTAssertTrue(r.succeeded, r.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("remote.txt").path))
    }
}
