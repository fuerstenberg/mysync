import XCTest
@testable import MySyncCore

/// „Übertragen und löschen“ und „nur manuell“.
final class RemoveSourceFilesTests: XCTestCase {
    let builder = RsyncCommandBuilder()

    func testOptionIsAdded() {
        let computer = makeComputer()
        var job = makeJob(computer: computer, direction: .pull)
        job.removeSourceFiles = true
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertTrue(args.contains("--remove-source-files"))
    }

    func testOptionDisablesDelete() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.deleteExtraneous = true
        job.removeSourceFiles = true
        XCTAssertFalse(job.effectiveDeleteExtraneous)
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertFalse(args.contains("--delete"))
        XCTAssertTrue(args.contains("--remove-source-files"))
    }

    func testWithoutOptionNothingChanges() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.deleteExtraneous = true
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertTrue(args.contains("--delete"))
        XCTAssertFalse(args.contains("--remove-source-files"))
    }

    func testArrows() {
        var job = makeJob(computer: makeComputer())
        XCTAssertEqual(job.arrow, "→")
        job.direction = .pull
        XCTAssertEqual(job.arrow, "←")
        job.removeSourceFiles = true
        XCTAssertEqual(job.arrow, "⇠")
        job.direction = .push
        XCTAssertEqual(job.arrow, "⇢")
    }

    func testOldConfigWithoutFieldDecodes() throws {
        let json = """
        {"id":"7E57D004-2B97-0E7A-B45F-5387367791CD","computerID":"7E57D004-2B97-0E7A-B45F-5387367791CE",
         "localPath":"~/Scans","remotePath":"/scan","direction":"pull","schedule":{"hourly":{}},
         "deleteExtraneous":false,"excludes":[".DS_Store"],"enabled":true}
        """
        let job = try JSONDecoder().decode(SyncJob.self, from: Data(json.utf8))
        XCTAssertFalse(job.removeSourceFiles)
        XCTAssertEqual(job.direction, .pull)
    }

    func testRoundTrip() throws {
        var job = makeJob(computer: makeComputer(), schedule: .manual, direction: .pull)
        job.removeSourceFiles = true
        let decoded = try JSONDecoder().decode(SyncJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(decoded, job)
    }
}

final class ManualScheduleTests: XCTestCase {
    func testDescriptionAndKind() {
        XCTAssertEqual(Schedule.manual.description, "nur manuell")
        XCTAssertEqual(Schedule.manual.kind, .manual)
        XCTAssertEqual(ScheduleKind.manual.label, "Nur manuell")
    }

    func testNeverDue() {
        let now = Date()
        XCTAssertFalse(Schedule.manual.isDue(lastAttempt: nil, now: now))
        XCTAssertFalse(Schedule.manual.isDue(lastAttempt: now.addingTimeInterval(-86_400 * 365), now: now))
    }

    func testNoRetryAfterFailure() {
        let computer = makeComputer()
        let job = makeJob(computer: computer, schedule: .manual)
        let now = Date()
        var config = AppConfig(computers: [computer], jobs: [job])
        config.statuses[job.id] = JobStatus(lastAttempt: now.addingTimeInterval(-3600), lastOutcome: .unreachable)
        XCTAssertTrue(Scheduler.dueJobs(in: config, now: now, running: []).isEmpty)
        config.statuses[job.id] = nil
        XCTAssertTrue(Scheduler.dueJobs(in: config, now: now, running: []).isEmpty)
    }

    func testCodable() throws {
        let data = try JSONEncoder().encode(Schedule.manual)
        XCTAssertEqual(try JSONDecoder().decode(Schedule.self, from: data), .manual)
    }
}
