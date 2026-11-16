import Foundation

public struct SyncResult: Equatable, Sendable {
    public var outcome: SyncOutcome
    public var message: String?

    public init(outcome: SyncOutcome, message: String? = nil) {
        self.outcome = outcome
        self.message = message
    }
}

public protocol SyncPerforming: Sendable {
    func perform(job: SyncJob, computer: Computer, settings: AppSettings) async -> SyncResult
}

/// Führt eine einzelne Synchronisierung aus: Erreichbarkeit prüfen, dann rsync starten.
public struct SyncEngine: SyncPerforming {
    public var runner: ProcessRunning
    public var reachability: ReachabilityChecking
    public var network: NetworkInfoProviding
    public var fileExists: @Sendable (String) -> Bool
    public var rsyncTimeout: TimeInterval
    public var reachabilityTimeout: TimeInterval

    public init(
        runner: ProcessRunning = ProcessRunner(),
        reachability: ReachabilityChecking = TCPReachability(),
        network: NetworkInfoProviding = SystemNetworkInfoProvider(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        rsyncTimeout: TimeInterval = 6 * 3600,
        reachabilityTimeout: TimeInterval = 5
    ) {
        self.runner = runner
        self.reachability = reachability
        self.network = network
        self.fileExists = fileExists
        self.rsyncTimeout = rsyncTimeout
        self.reachabilityTimeout = reachabilityTimeout
    }

    public func perform(job: SyncJob, computer: Computer, settings: AppSettings) async -> SyncResult {
        // 1. Konfiguration prüfen
        if let problem = Self.validate(job: job, computer: computer) {
            return SyncResult(outcome: .failed, message: problem)
        }
        let localPath = RsyncCommandBuilder.expandLocal(job.localPath)
        if job.direction == .push, !fileExists(localPath) {
            return SyncResult(outcome: .failed, message: "Lokaler Ordner nicht gefunden: \(localPath)")
        }
        guard let rsync = RsyncLocator.locate(customPath: settings.rsyncPath) else {
            return SyncResult(outcome: .failed, message: "rsync wurde nicht gefunden.")
        }

        // 2. Erreichbarkeit – bei Ausfall entscheidet das Netzwerk, ob das ein Fehler ist.
        let reachable = await reachability.isReachable(
            host: computer.host, port: computer.port, timeout: reachabilityTimeout
        )
        if !reachable {
            let match = NetworkMatcher.match(computer: computer, snapshot: network.snapshot())
            if match.expectsReachable {
                return SyncResult(outcome: .unreachable, message: "\(computer.displayName) ist nicht erreichbar.")
            }
            return SyncResult(outcome: .skippedNotInNetwork, message: "Nicht im Netzwerk von \(computer.displayName).")
        }

        // 3. rsync ausführen
        let flavor = await Self.detectFlavor(rsyncPath: rsync, runner: runner)
        let builder = RsyncCommandBuilder(rsyncEscapesRemotePaths: flavor.escapesRemotePaths)
        let args = builder.arguments(for: job, computer: computer)

        do {
            let result = try await runner.run(executable: rsync, arguments: args, timeout: rsyncTimeout)
            if result.succeeded {
                return SyncResult(outcome: .success)
            }
            if result.timedOut {
                return SyncResult(outcome: .failed, message: "Zeitüberschreitung beim Synchronisieren.")
            }
            return SyncResult(outcome: .failed, message: Self.errorMessage(exitCode: result.exitCode, stderr: result.stderr))
        } catch {
            return SyncResult(outcome: .failed, message: "rsync konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    public static func validate(job: SyncJob, computer: Computer) -> String? {
        if computer.host.trimmingCharacters(in: .whitespaces).isEmpty { return "Kein Host angegeben." }
        if job.localPath.trimmingCharacters(in: .whitespaces).isEmpty { return "Kein lokaler Ordner angegeben." }
        if job.remotePath.trimmingCharacters(in: .whitespaces).isEmpty { return "Kein entfernter Ordner angegeben." }
        if !(1...65535).contains(computer.port) { return "Ungültiger Port \(computer.port)." }
        return nil
    }

    static func detectFlavor(rsyncPath: String, runner: ProcessRunning) async -> RsyncFlavor {
        guard let result = try? await runner.run(executable: rsyncPath, arguments: ["--version"], timeout: 10) else {
            return .unknown
        }
        return RsyncFlavor.parse(versionOutput: result.stdout + result.stderr)
    }

    /// Kurze, lesbare Fehlermeldung aus stderr bzw. dem Exit-Code.
    public static func errorMessage(exitCode: Int32, stderr: String) -> String {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let line = lines.first(where: { $0.localizedCaseInsensitiveContains("error") || $0.contains("denied") })
            ?? lines.last {
            return String(line.prefix(200))
        }
        switch exitCode {
        case 23: return "Einige Dateien konnten nicht übertragen werden (Code 23)."
        case 255: return "SSH-Verbindung fehlgeschlagen (Code 255)."
        default: return "rsync wurde mit Code \(exitCode) beendet."
        }
    }
}
