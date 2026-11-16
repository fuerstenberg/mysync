import XCTest
@testable import MySyncCore

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    var computer: Computer!
    var job: SyncJob!
    var store: InMemoryConfigStore!
    var engine: FakeEngine!
    var notifier: RecordingNotifier!
    var clock: MutableClock!

    override func setUp() async throws {
        computer = makeComputer()
        job = makeJob(computer: computer, schedule: .everyMinutes(10))
        store = InMemoryConfigStore(AppConfig(computers: [computer], jobs: [job]))
        engine = FakeEngine()
        notifier = RecordingNotifier()
        clock = MutableClock(TestCalendar.date(2026, 11, 16, 12, 0))
    }

    func makeCoordinator() -> SyncCoordinator {
        let clock = self.clock!
        return SyncCoordinator(store: store, engine: engine, notifier: notifier, clock: { clock.now })
    }

    func testTickRunsDueJobAndStoresStatus() async throws {
        let c = makeCoordinator()
        await c.tick()
        XCTAssertEqual(engine.performedJobs, [job.id])
        XCTAssertEqual(c.config.status(for: job).lastOutcome, .success)
        XCTAssertEqual(c.indicator, .ok)
        XCTAssertEqual(try store.load().statuses[job.id]?.lastOutcome, .success)
    }

    func testTickDoesNotRepeatBeforeInterval() async {
        let c = makeCoordinator()
        await c.tick()
        clock.advance(5 * 60)
        await c.tick()
        XCTAssertEqual(engine.performedJobs.count, 1)
        clock.advance(5 * 60)
        await c.tick()
        XCTAssertEqual(engine.performedJobs.count, 2)
    }

    func testManualSyncIgnoresSchedule() async {
        let c = makeCoordinator()
        await c.tick()
        await c.sync(jobID: job.id)
        XCTAssertEqual(engine.performedJobs.count, 2)
    }

    func testUnreachableNotifiesOnceAndShowsRed() async {
        engine.defaultResult = SyncResult(outcome: .unreachable, message: "NAS ist nicht erreichbar.")
        let c = makeCoordinator()
        await c.sync(jobID: job.id)
        await c.sync(jobID: job.id)
        XCTAssertEqual(notifier.count, 1)
        XCTAssertEqual(notifier.messages.first?.title, "NAS nicht erreichbar")
        XCTAssertEqual(c.indicator, .error)
    }

    func testSkippedDoesNotNotify() async {
        engine.defaultResult = SyncResult(outcome: .skippedNotInNetwork)
        let c = makeCoordinator()
        await c.sync(jobID: job.id)
        XCTAssertEqual(notifier.count, 0)
        XCTAssertEqual(c.indicator, .none)
    }

    func testNoParallelRunsOfSameJob() async {
        engine.delayNanoseconds = 100_000_000
        let c = makeCoordinator()
        async let a: Void = c.sync(jobID: job.id)
        async let b: Void = c.sync(jobID: job.id)
        _ = await (a, b)
        XCTAssertEqual(engine.performedJobs.count, 1)
    }

    func testRunningSetDuringSync() async {
        engine.delayNanoseconds = 100_000_000
        let c = makeCoordinator()
        let task = Task { await c.sync(jobID: job.id) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(c.running.contains(job.id))
        await task.value
        XCTAssertFalse(c.running.contains(job.id))
    }

    func testSyncAllRunsEnabledJobs() async {
        var disabled = makeJob(computer: computer)
        disabled.enabled = false
        let c = makeCoordinator()
        c.upsert(job: disabled)
        await c.syncAll()
        XCTAssertEqual(engine.performedJobs, [job.id])
    }

    func testRemoveComputerRemovesJobsAndStatus() async {
        let c = makeCoordinator()
        await c.sync(jobID: job.id)
        c.removeComputer(id: computer.id)
        XCTAssertTrue(c.config.jobs.isEmpty)
        XCTAssertTrue(c.config.statuses.isEmpty)
        XCTAssertTrue(c.config.computers.isEmpty)
    }

    func testUpsertJobResetsStatusWhenTargetChanges() async {
        let c = makeCoordinator()
        await c.sync(jobID: job.id)
        var changed = job!
        changed.schedule = .hourly
        c.upsert(job: changed)
        XCTAssertNotNil(c.config.statuses[job.id], "Nur Intervall geändert → Status bleibt")
        changed.remotePath = "/anderer/ordner"
        c.upsert(job: changed)
        XCTAssertNil(c.config.statuses[job.id])
    }

    func testUpsertComputerAddsAndUpdates() {
        let c = makeCoordinator()
        var other = Computer(name: "Mac mini", host: "mini.local")
        c.upsert(computer: other)
        XCTAssertEqual(c.config.computers.count, 2)
        other.port = 2200
        c.upsert(computer: other)
        XCTAssertEqual(c.config.computers.count, 2)
        XCTAssertEqual(c.config.computers.last?.port, 2200)
    }

    func testDeletedJobDuringSyncIsNotRestored() async {
        engine.delayNanoseconds = 100_000_000
        let c = makeCoordinator()
        let task = Task { await c.sync(jobID: job.id) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        c.removeJob(id: job.id)
        await task.value
        XCTAssertNil(c.config.statuses[job.id])
    }
}
