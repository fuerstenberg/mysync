import XCTest
@testable import MySyncCore

final class RsyncCommandBuilderTests: XCTestCase {
    let builder = RsyncCommandBuilder()

    func testPushArguments() {
        let computer = makeComputer()
        let job = makeJob(computer: computer)
        let args = builder.arguments(for: job, computer: computer)

        XCTAssertEqual(Array(args.prefix(2)), ["-az", "--partial"])
        XCTAssertEqual(args.suffix(2), ["/Users/test/Fotos/", "rene@nas.local:/volume1/Fotos/"])
        XCTAssertFalse(args.contains("--delete"))
        XCTAssertTrue(args.contains("--exclude=.DS_Store"))
    }

    func testPullSwapsSourceAndDestination() {
        let computer = makeComputer()
        let job = makeJob(computer: computer, direction: .pull)
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertEqual(args.suffix(2), ["rene@nas.local:/volume1/Fotos/", "/Users/test/Fotos/"])
    }

    func testSSHOptions() {
        var computer = makeComputer()
        computer.port = 2222
        computer.sshKeyPath = "/Users/test/.ssh/id_ed25519"
        let job = makeJob(computer: computer)
        let args = builder.arguments(for: job, computer: computer)

        guard let i = args.firstIndex(of: "-e") else { return XCTFail("-e fehlt") }
        let ssh = args[i + 1]
        XCTAssertTrue(ssh.hasPrefix("/usr/bin/ssh -p 2222"))
        XCTAssertTrue(ssh.contains("-o BatchMode=yes"))
        XCTAssertTrue(ssh.contains("-o ConnectTimeout=10"))
        XCTAssertTrue(ssh.contains("-i /Users/test/.ssh/id_ed25519"))
    }

    func testSSHKeyWithSpaceIsQuoted() {
        var computer = makeComputer()
        computer.sshKeyPath = "/Users/test/My Keys/id"
        XCTAssertTrue(builder.sshCommand(for: computer).contains("-i '/Users/test/My Keys/id'"))
    }

    func testNoKeyMeansNoIdentityOption() {
        XCTAssertFalse(builder.sshCommand(for: makeComputer()).contains("-i"))
    }

    func testDeleteAndExcludes() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.deleteExtraneous = true
        job.excludes = ["*.tmp", "  ", "node_modules/"]
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertTrue(args.contains("--delete"))
        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--exclude=node_modules/"))
        XCTAssertEqual(args.filter { $0.hasPrefix("--exclude") }.count, 2)
    }

    func testTrailingSlashNotDoubled() {
        XCTAssertEqual(RsyncCommandBuilder.withTrailingSlash("/a/"), "/a/")
        XCTAssertEqual(RsyncCommandBuilder.withTrailingSlash("/a"), "/a/")
    }

    func testTildeIsExpandedLocally() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.localPath = "~/Dokumente"
        let args = builder.arguments(for: job, computer: computer)
        XCTAssertEqual(args[args.count - 2], NSHomeDirectory() + "/Dokumente/")
    }

    func testRemotePathWithSpacesIsEscapedForOpenrsync() {
        XCTAssertEqual(RsyncCommandBuilder.remotePathArgument("/data/Meine Fotos"), "/data/Meine\\ Fotos/")
        XCTAssertEqual(RsyncCommandBuilder.remotePathArgument("~/Backup (alt)"), "~/Backup\\ \\(alt\\)/")
    }

    func testRemotePathNotEscapedForModernGNURsync() {
        let computer = makeComputer()
        var job = makeJob(computer: computer)
        job.remotePath = "/data/Meine Fotos"
        let modern = RsyncCommandBuilder(rsyncEscapesRemotePaths: true)
        XCTAssertEqual(modern.arguments(for: job, computer: computer).last, "rene@nas.local:/data/Meine Fotos/")
    }

    func testEmptyUserUsesHostOnly() {
        var computer = makeComputer()
        computer.user = ""
        XCTAssertEqual(computer.sshDestination, "nas.local")
    }

    func testLocalArguments() {
        let computer = makeComputer()
        let job = makeJob(computer: computer)
        let args = builder.localArguments(for: job, destination: "/tmp/ziel")
        XCTAssertEqual(args.suffix(2), ["/Users/test/Fotos/", "/tmp/ziel/"])
        XCTAssertFalse(args.contains("-e"))
    }
}

final class RsyncLocatorTests: XCTestCase {
    func testPrefersHomebrew() {
        let found = RsyncLocator.locate(customPath: "") { _ in true }
        XCTAssertEqual(found, "/opt/homebrew/bin/rsync")
    }

    func testFallsBackToSystem() {
        let found = RsyncLocator.locate(customPath: "") { $0 == "/usr/bin/rsync" }
        XCTAssertEqual(found, "/usr/bin/rsync")
    }

    func testCustomPath() {
        XCTAssertEqual(RsyncLocator.locate(customPath: "/x/rsync") { $0 == "/x/rsync" }, "/x/rsync")
        XCTAssertNil(RsyncLocator.locate(customPath: "/x/rsync") { _ in false })
    }

    func testNothingFound() {
        XCTAssertNil(RsyncLocator.locate(customPath: "") { _ in false })
    }
}

final class RsyncFlavorTests: XCTestCase {
    func testOpenrsync() {
        XCTAssertEqual(RsyncFlavor.parse(versionOutput: "openrsync: protocol version 29\nrsync version 2.6.9 compatible"), .openrsync)
    }

    func testGNU() {
        let flavor = RsyncFlavor.parse(versionOutput: "rsync  version 3.2.7  protocol version 31\nCopyright")
        XCTAssertEqual(flavor, .gnu(major: 3, minor: 2, patch: 7))
        XCTAssertTrue(flavor.escapesRemotePaths)
    }

    func testOldGNUDoesNotEscape() {
        let flavor = RsyncFlavor.parse(versionOutput: "rsync  version 3.2.3  protocol version 31")
        XCTAssertFalse(flavor.escapesRemotePaths)
        XCTAssertFalse(RsyncFlavor.parse(versionOutput: "rsync  version 2.6.9  protocol version 29").escapesRemotePaths)
    }

    func testUnknown() {
        XCTAssertEqual(RsyncFlavor.parse(versionOutput: "irgendwas"), .unknown)
        XCTAssertFalse(RsyncFlavor.unknown.escapesRemotePaths)
    }
}
