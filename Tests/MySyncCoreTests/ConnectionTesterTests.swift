import XCTest
@testable import MySyncCore

final class ConnectionTesterTests: XCTestCase {
    func testArguments() {
        var computer = makeComputer()
        computer.port = 2222
        computer.sshKeyPath = "~/.ssh/nas"
        let args = RsyncCommandBuilder().sshTestArguments(for: computer)
        XCTAssertEqual(Array(args.prefix(2)), ["-p", "2222"])
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains(NSHomeDirectory() + "/.ssh/nas"))
        XCTAssertEqual(args.suffix(2), ["rene@nas.local", "echo mysync-ok"])
    }

    func testInterpret() {
        XCTAssertEqual(ConnectionTester.interpret(ProcessResult(exitCode: 0, stdout: "mysync-ok\n")), .success)
        XCTAssertEqual(ConnectionTester.interpret(ProcessResult(exitCode: 0, stdout: "")),
                       .failure("Verbindung fehlgeschlagen: Code 0"))
        XCTAssertTrue(ConnectionTester.interpret(ProcessResult(exitCode: 255, stderr: "rene@nas: Permission denied (publickey).")).message.contains("ssh-copy-id"))
        XCTAssertTrue(ConnectionTester.interpret(ProcessResult(exitCode: 255, stderr: "ssh: Could not resolve hostname nas: nodename")).message.contains("aufgelöst"))
        XCTAssertTrue(ConnectionTester.interpret(ProcessResult(exitCode: 255, stderr: "ssh: connect to host nas port 22: Connection refused")).message.contains("Entfernte Anmeldung"))
        XCTAssertTrue(ConnectionTester.interpret(ProcessResult(exitCode: 255, stderr: "ssh: connect to host nas port 22: Operation timed out")).message.contains("nicht erreichbar"))
        XCTAssertTrue(ConnectionTester.interpret(ProcessResult(exitCode: 255, timedOut: true)).message.contains("Zeitüberschreitung"))
    }

    func testEmptyHost() async {
        var computer = makeComputer()
        computer.host = ""
        let outcome = await ConnectionTester(runner: FakeRunner()).test(computer)
        XCTAssertEqual(outcome, .failure("Bitte zuerst einen Host angeben."))
    }

    func testUsesRunner() async {
        let runner = FakeRunner()
        runner.result = ProcessResult(exitCode: 0, stdout: "mysync-ok\n")
        let outcome = await ConnectionTester(runner: runner).test(makeComputer())
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(runner.syncCalls.first?.last, "echo mysync-ok")
    }
}
