import XCTest
@testable import MySyncCore

final class NotificationPolicyTests: XCTestCase {
    let now = TestCalendar.date(2026, 11, 16, 12, 0)

    func testSuccessUpdatesStatusWithoutNotification() {
        let d = NotificationPolicy.apply(result: SyncResult(outcome: .success), to: JobStatus(), at: now)
        XCTAssertFalse(d.shouldNotify)
        XCTAssertEqual(d.status.lastSuccess, now)
        XCTAssertEqual(d.status.lastAttempt, now)
        XCTAssertEqual(d.status.lastOutcome, .success)
    }

    func testUnreachableInNetworkNotifiesOnce() {
        let first = NotificationPolicy.apply(result: SyncResult(outcome: .unreachable), to: JobStatus(), at: now)
        XCTAssertTrue(first.shouldNotify)
        let second = NotificationPolicy.apply(result: SyncResult(outcome: .unreachable), to: first.status, at: now + 300)
        XCTAssertFalse(second.shouldNotify, "Pro Ausfall nur eine Meldung")
    }

    func testFailureNotifies() {
        let d = NotificationPolicy.apply(result: SyncResult(outcome: .failed, message: "x"), to: JobStatus(), at: now)
        XCTAssertTrue(d.shouldNotify)
        XCTAssertEqual(d.status.lastMessage, "x")
    }

    func testSuccessResetsDedupe() {
        let fail = NotificationPolicy.apply(result: SyncResult(outcome: .failed), to: JobStatus(), at: now)
        let ok = NotificationPolicy.apply(result: SyncResult(outcome: .success), to: fail.status, at: now + 60)
        XCTAssertFalse(ok.status.notifiedForCurrentFailure)
        let failAgain = NotificationPolicy.apply(result: SyncResult(outcome: .failed), to: ok.status, at: now + 120)
        XCTAssertTrue(failAgain.shouldNotify)
    }

    func testSkippedNeverNotifiesAndKeepsLastSuccess() {
        let previous = JobStatus(lastAttempt: now - 3600, lastSuccess: now - 3600, lastOutcome: .success)
        let d = NotificationPolicy.apply(result: SyncResult(outcome: .skippedNotInNetwork), to: previous, at: now)
        XCTAssertFalse(d.shouldNotify)
        XCTAssertEqual(d.status.lastSuccess, now - 3600)
        XCTAssertEqual(d.status.lastOutcome, .skippedNotInNetwork)
    }

    func testSkippedDoesNotResetDedupe() {
        let fail = NotificationPolicy.apply(result: SyncResult(outcome: .unreachable), to: JobStatus(), at: now)
        let skip = NotificationPolicy.apply(result: SyncResult(outcome: .skippedNotInNetwork), to: fail.status, at: now + 60)
        let again = NotificationPolicy.apply(result: SyncResult(outcome: .unreachable), to: skip.status, at: now + 120)
        XCTAssertFalse(again.shouldNotify)
    }
}

final class StatusAggregatorTests: XCTestCase {
    func config(_ outcomes: [SyncOutcome?], enabled: [Bool]? = nil) -> AppConfig {
        let computer = makeComputer()
        var config = AppConfig(computers: [computer])
        for (i, outcome) in outcomes.enumerated() {
            var job = makeJob(computer: computer)
            job.enabled = enabled?[i] ?? true
            config.jobs.append(job)
            if let outcome { config.statuses[job.id] = JobStatus(lastOutcome: outcome) }
        }
        return config
    }

    func testNothingRunYet() {
        XCTAssertEqual(StatusAggregator.indicator(for: AppConfig()), .none)
        XCTAssertEqual(StatusAggregator.indicator(for: config([nil, nil])), .none)
    }

    func testAllSuccessIsGreen() {
        XCTAssertEqual(StatusAggregator.indicator(for: config([.success, .success])), .ok)
    }

    func testAnyFailureIsRed() {
        XCTAssertEqual(StatusAggregator.indicator(for: config([.success, .failed])), .error)
        XCTAssertEqual(StatusAggregator.indicator(for: config([.unreachable, .success])), .error)
    }

    func testSkippedIsNeutral() {
        XCTAssertEqual(StatusAggregator.indicator(for: config([.success, .skippedNotInNetwork])), .ok)
        XCTAssertEqual(StatusAggregator.indicator(for: config([.skippedNotInNetwork])), .none)
    }

    func testDisabledJobsAreIgnored() {
        XCTAssertEqual(StatusAggregator.indicator(for: config([.success, .failed], enabled: [true, false])), .ok)
    }
}

final class SchedulerTests: XCTestCase {
    let cal = TestCalendar.berlin
    let now = TestCalendar.date(2026, 11, 16, 12, 0)

    func testNewJobsAreDue() {
        let computer = makeComputer()
        let job = makeJob(computer: computer)
        let config = AppConfig(computers: [computer], jobs: [job])
        XCTAssertEqual(Scheduler.dueJobs(in: config, now: now, running: [], calendar: cal).map(\.id), [job.id])
    }

    func testRecentSuccessNotDue() {
        let computer = makeComputer()
        let job = makeJob(computer: computer, schedule: .hourly)
        var config = AppConfig(computers: [computer], jobs: [job])
        config.statuses[job.id] = JobStatus(lastAttempt: now - 1800, lastSuccess: now - 1800, lastOutcome: .success)
        XCTAssertTrue(Scheduler.dueJobs(in: config, now: now, running: [], calendar: cal).isEmpty)
        XCTAssertEqual(Scheduler.dueJobs(in: config, now: now + 1800, running: [], calendar: cal).count, 1)
    }

    func testRunningJobsAreSkipped() {
        let computer = makeComputer()
        let job = makeJob(computer: computer)
        let config = AppConfig(computers: [computer], jobs: [job])
        XCTAssertTrue(Scheduler.dueJobs(in: config, now: now, running: [job.id], calendar: cal).isEmpty)
    }

    func testDisabledAndOrphanedJobsAreSkipped() {
        let computer = makeComputer()
        var disabled = makeJob(computer: computer)
        disabled.enabled = false
        let orphan = SyncJob(computerID: UUID(), localPath: "/a", remotePath: "/b")
        let config = AppConfig(computers: [computer], jobs: [disabled, orphan])
        XCTAssertTrue(Scheduler.dueJobs(in: config, now: now, running: [], calendar: cal).isEmpty)
    }

    func testDailyRetriesSoonerAfterSkip() {
        // Täglich 12:00; um 12:00 war ich unterwegs → nach 5 Minuten erneut versuchen, nicht erst morgen.
        let computer = makeComputer()
        let job = makeJob(computer: computer, schedule: .daily(hour: 12, minute: 0))
        let status = JobStatus(lastAttempt: now, lastOutcome: .skippedNotInNetwork)
        XCTAssertEqual(Scheduler.nextRun(for: job, status: status, calendar: cal), now + Scheduler.retryInterval)
    }

    func testRetryNeverLaterThanRegularSchedule() {
        let computer = makeComputer()
        let job = makeJob(computer: computer, schedule: .everyMinutes(1))
        let status = JobStatus(lastAttempt: now, lastOutcome: .unreachable)
        XCTAssertEqual(Scheduler.nextRun(for: job, status: status, calendar: cal), now + 60)
    }

    func testSuccessUsesRegularSchedule() {
        let computer = makeComputer()
        let job = makeJob(computer: computer, schedule: .daily(hour: 12, minute: 0))
        let status = JobStatus(lastAttempt: now, lastSuccess: now, lastOutcome: .success)
        XCTAssertEqual(Scheduler.nextRun(for: job, status: status, calendar: cal), TestCalendar.date(2026, 11, 17, 12, 0))
    }
}
