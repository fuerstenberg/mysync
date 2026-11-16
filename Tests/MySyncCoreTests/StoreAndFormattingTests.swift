import XCTest
@testable import MySyncCore

final class ConfigStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mysync-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileGivesEmptyConfig() throws {
        let store = ConfigStore(fileURL: dir.appendingPathComponent("config.json"))
        XCTAssertEqual(try store.load(), AppConfig())
    }

    func testRoundTrip() throws {
        let store = ConfigStore(fileURL: dir.appendingPathComponent("sub/config.json"))
        let computer = makeComputer(ssids: ["Zuhause"], subnets: ["192.168.1.0/24"])
        let job = makeJob(computer: computer, schedule: .daily(hour: 12, minute: 0), direction: .pull)
        var config = AppConfig(computers: [computer], jobs: [job], settings: AppSettings(rsyncPath: "/opt/homebrew/bin/rsync"))
        config.statuses[job.id] = JobStatus(lastAttempt: Date(timeIntervalSince1970: 1_700_000_000),
                                            lastSuccess: Date(timeIntervalSince1970: 1_700_000_000),
                                            lastOutcome: .success)
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testCorruptFileThrows() throws {
        let url = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{kaputt".utf8).write(to: url)
        XCTAssertThrowsError(try ConfigStore(fileURL: url).load())
    }

    func testVersionIsWritten() throws {
        let url = dir.appendingPathComponent("config.json")
        try ConfigStore(fileURL: url).save(AppConfig())
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(json.contains("\"version\" : 1"))
    }

    func testDefaultURL() {
        XCTAssertTrue(ConfigStore.defaultURL.path.hasSuffix("Application Support/mysync/config.json"))
    }
}

final class FormattingTests: XCTestCase {
    let cal = TestCalendar.berlin
    let now = TestCalendar.date(2026, 11, 16, 15, 30)

    func testRelative() {
        XCTAssertEqual(SyncFormatting.relative(nil, now: now, calendar: cal), "noch nie")
        XCTAssertEqual(SyncFormatting.relative(now - 20, now: now, calendar: cal), "gerade eben")
        XCTAssertEqual(SyncFormatting.relative(now - 5 * 60, now: now, calendar: cal), "vor 5 Min.")
        XCTAssertEqual(SyncFormatting.relative(TestCalendar.date(2026, 11, 16, 12, 0), now: now, calendar: cal), "heute 12:00")
        XCTAssertEqual(SyncFormatting.relative(TestCalendar.date(2026, 11, 15, 8, 5), now: now, calendar: cal), "gestern 08:05")
        XCTAssertEqual(SyncFormatting.relative(TestCalendar.date(2026, 11, 2, 9, 0), now: now, calendar: cal), "02.11. 09:00")
    }

    func testStatusLine() {
        let ok = JobStatus(lastSuccess: now - 600, lastOutcome: .success)
        XCTAssertEqual(SyncFormatting.statusLine(ok, isRunning: false, now: now, calendar: cal), "✓ zuletzt vor 10 Min.")
        XCTAssertEqual(SyncFormatting.statusLine(ok, isRunning: true, now: now, calendar: cal), "⟳ wird synchronisiert …")
        XCTAssertEqual(SyncFormatting.statusLine(JobStatus(), isRunning: false, now: now, calendar: cal), "noch nicht synchronisiert")
        XCTAssertEqual(SyncFormatting.statusLine(JobStatus(lastOutcome: .unreachable), isRunning: false, now: now, calendar: cal),
                       "✗ nicht erreichbar – zuletzt erfolgreich: noch nie")
    }

    func testModelHelpers() {
        var computer = makeComputer()
        XCTAssertEqual(computer.displayName, "NAS")
        computer.name = " "
        XCTAssertEqual(computer.displayName, "nas.local")
        XCTAssertEqual(makeJob(computer: computer).folderName, "Fotos")
        XCTAssertEqual(SyncDirection.push.arrow, "→")
        XCTAssertEqual(SyncDirection.pull.arrow, "←")
    }
}
