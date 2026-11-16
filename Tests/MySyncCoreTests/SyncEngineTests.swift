import XCTest
@testable import MySyncCore

final class SyncEngineTests: XCTestCase {
    let settings = AppSettings(rsyncPath: "/bin/echo") // existiert immer; der Runner ist ohnehin gefälscht

    func engine(runner: FakeRunner = FakeRunner(), reachable: Bool = true,
                snapshot: NetworkSnapshot = NetworkSnapshot(), localExists: Bool = true) -> SyncEngine {
        SyncEngine(runner: runner, reachability: FakeReachability(reachable: reachable),
                   network: FakeNetwork(snap: snapshot), fileExists: { _ in localExists })
    }

    func testSuccess() async {
        let runner = FakeRunner()
        let computer = makeComputer()
        let result = await engine(runner: runner).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result, SyncResult(outcome: .success))
        XCTAssertEqual(runner.syncCalls.count, 1)
        XCTAssertEqual(runner.syncCalls.first?.last, "rene@nas.local:/volume1/Fotos/")
    }

    func testUnreachableInHomeNetwork() async {
        let computer = makeComputer(ssids: ["Zuhause"])
        let result = await engine(reachable: false, snapshot: NetworkSnapshot(ssid: "Zuhause"))
            .perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .unreachable)
    }

    func testUnreachableOutsideNetworkIsSkipped() async {
        let runner = FakeRunner()
        let computer = makeComputer(ssids: ["Zuhause"])
        let result = await engine(runner: runner, reachable: false, snapshot: NetworkSnapshot(ssid: "Bahn-WLAN"))
            .perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .skippedNotInNetwork)
        XCTAssertTrue(runner.syncCalls.isEmpty)
    }

    func testUnreachableWithoutRulesCountsAsError() async {
        let computer = makeComputer()
        let result = await engine(reachable: false).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .unreachable)
    }

    func testRsyncFailure() async {
        let runner = FakeRunner()
        runner.result = ProcessResult(exitCode: 23, stderr: "rsync: send_files failed\nrsync error: some files could not be transferred (code 23)")
        let computer = makeComputer()
        let result = await engine(runner: runner).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.message, "rsync error: some files could not be transferred (code 23)")
    }

    func testTimeout() async {
        let runner = FakeRunner()
        runner.result = ProcessResult(exitCode: 15, timedOut: true)
        let computer = makeComputer()
        let result = await engine(runner: runner).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.message, "Zeitüberschreitung beim Synchronisieren.")
    }

    func testLaunchError() async {
        struct Boom: Error {}
        let runner = FakeRunner()
        runner.error = Boom()
        let computer = makeComputer()
        let result = await engine(runner: runner).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.message?.hasPrefix("rsync konnte nicht gestartet werden") ?? false)
    }

    func testMissingLocalFolderForPush() async {
        let computer = makeComputer()
        let result = await engine(localExists: false).perform(job: makeJob(computer: computer), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.message?.contains("Lokaler Ordner nicht gefunden") ?? false)
    }

    func testMissingLocalFolderIsFineForPull() async {
        let computer = makeComputer()
        let result = await engine(localExists: false)
            .perform(job: makeJob(computer: computer, direction: .pull), computer: computer, settings: settings)
        XCTAssertEqual(result.outcome, .success)
    }

    func testMissingRsync() async {
        let computer = makeComputer()
        let result = await engine().perform(job: makeJob(computer: computer), computer: computer,
                                            settings: AppSettings(rsyncPath: "/gibt/es/nicht"))
        XCTAssertEqual(result, SyncResult(outcome: .failed, message: "rsync wurde nicht gefunden."))
    }

    func testModernRsyncGetsUnescapedRemotePath() async {
        let runner = FakeRunner()
        runner.versionOutput = "rsync  version 3.3.0  protocol version 31"
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.remotePath = "/data/Meine Fotos"
        _ = await engine(runner: runner).perform(job: job, computer: computer, settings: settings)
        XCTAssertEqual(runner.syncCalls.first?.last, "rene@nas.local:/data/Meine Fotos/")
    }

    func testValidation() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        XCTAssertNil(SyncEngine.validate(job: job, computer: computer))

        var noHost = computer; noHost.host = " "
        XCTAssertEqual(SyncEngine.validate(job: job, computer: noHost), "Kein Host angegeben.")

        var badPort = computer; badPort.port = 0
        XCTAssertEqual(SyncEngine.validate(job: job, computer: badPort), "Ungültiger Port 0.")

        job.remotePath = ""
        XCTAssertEqual(SyncEngine.validate(job: job, computer: computer), "Kein entfernter Ordner angegeben.")
        job.localPath = ""
        XCTAssertEqual(SyncEngine.validate(job: job, computer: computer), "Kein lokaler Ordner angegeben.")
    }

    func testErrorMessageFallbacks() {
        XCTAssertEqual(SyncEngine.errorMessage(exitCode: 255, stderr: ""), "SSH-Verbindung fehlgeschlagen (Code 255).")
        XCTAssertEqual(SyncEngine.errorMessage(exitCode: 23, stderr: "  \n"), "Einige Dateien konnten nicht übertragen werden (Code 23).")
        XCTAssertEqual(SyncEngine.errorMessage(exitCode: 12, stderr: ""), "rsync wurde mit Code 12 beendet.")
        XCTAssertEqual(SyncEngine.errorMessage(exitCode: 255, stderr: "rene@nas: Permission denied (publickey)."),
                       "rene@nas: Permission denied (publickey).")
    }
}
