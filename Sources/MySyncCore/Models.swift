import Foundation

/// Ein entfernter Computer, der per SSH erreichbar ist.
public struct Computer: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String
    public var port: Int
    /// Optionaler Pfad zu einem privaten SSH-Schlüssel. Leer = Standard aus ~/.ssh.
    public var sshKeyPath: String
    /// WLAN-Namen, in denen dieser Computer erreichbar sein sollte.
    public var ssids: [String]
    /// Subnetze in CIDR-Schreibweise (z. B. 192.168.1.0/24) als Fallback, etwa für LAN-Kabel.
    public var subnets: [String]

    public init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        user: String = NSUserName(),
        port: Int = 22,
        sshKeyPath: String = "",
        ssids: [String] = [],
        subnets: [String] = []
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.sshKeyPath = sshKeyPath
        self.ssids = ssids
        self.subnets = subnets
    }

    /// Anzeigename: Name, sonst Host.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
    }

    /// `user@host` bzw. nur `host`, wenn kein Benutzer gesetzt ist.
    public var sshDestination: String {
        user.isEmpty ? host : "\(user)@\(host)"
    }
}

/// Richtung einer Synchronisierung.
public enum SyncDirection: String, Codable, CaseIterable, Sendable {
    /// Lokal → entfernter Computer
    case push
    /// Entfernter Computer → lokal
    case pull

    public var label: String {
        switch self {
        case .push: return "Senden (Mac → Computer)"
        case .pull: return "Holen (Computer → Mac)"
        }
    }

    public var arrow: String {
        switch self {
        case .push: return "→"
        case .pull: return "←"
        }
    }
}

/// Ein zu synchronisierendes Ordnerpaar.
public struct SyncJob: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var computerID: UUID
    public var localPath: String
    public var remotePath: String
    public var direction: SyncDirection
    public var schedule: Schedule
    /// Dateien im Ziel löschen, die in der Quelle fehlen (`--delete`).
    public var deleteExtraneous: Bool
    public var excludes: [String]
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        computerID: UUID,
        localPath: String = "",
        remotePath: String = "",
        direction: SyncDirection = .push,
        schedule: Schedule = .hourly,
        deleteExtraneous: Bool = false,
        excludes: [String] = [".DS_Store"],
        enabled: Bool = true
    ) {
        self.id = id
        self.computerID = computerID
        self.localPath = localPath
        self.remotePath = remotePath
        self.direction = direction
        self.schedule = schedule
        self.deleteExtraneous = deleteExtraneous
        self.excludes = excludes
        self.enabled = enabled
    }

    /// Kurzer Ordnername für das Menü.
    public var folderName: String {
        let name = (localPath as NSString).lastPathComponent
        return name.isEmpty ? localPath : name
    }
}

/// Ergebnis des letzten Synchronisierungsversuchs.
public enum SyncOutcome: String, Codable, Sendable {
    case success
    /// rsync ist mit einem Fehler beendet worden.
    case failed
    /// Computer nicht erreichbar, obwohl wir in seinem Netzwerk sind.
    case unreachable
    /// Computer nicht erreichbar, wir sind aber gar nicht in seinem Netzwerk – kein Fehler.
    case skippedNotInNetwork
}

public struct JobStatus: Codable, Hashable, Sendable {
    /// Zeitpunkt des letzten Versuchs (egal mit welchem Ergebnis).
    public var lastAttempt: Date?
    /// Zeitpunkt der letzten erfolgreichen Synchronisierung.
    public var lastSuccess: Date?
    public var lastOutcome: SyncOutcome?
    public var lastMessage: String?
    /// Wurde für den aktuellen Ausfall schon benachrichtigt?
    public var notifiedForCurrentFailure: Bool

    public init(
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        lastOutcome: SyncOutcome? = nil,
        lastMessage: String? = nil,
        notifiedForCurrentFailure: Bool = false
    ) {
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.lastOutcome = lastOutcome
        self.lastMessage = lastMessage
        self.notifiedForCurrentFailure = notifiedForCurrentFailure
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    /// Eigener rsync-Pfad. Leer = automatisch suchen.
    public var rsyncPath: String

    public init(rsyncPath: String = "") {
        self.rsyncPath = rsyncPath
    }
}

/// Die gesamte gespeicherte Konfiguration.
public struct AppConfig: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var computers: [Computer]
    public var jobs: [SyncJob]
    public var statuses: [UUID: JobStatus]
    public var settings: AppSettings

    public init(
        computers: [Computer] = [],
        jobs: [SyncJob] = [],
        statuses: [UUID: JobStatus] = [:],
        settings: AppSettings = AppSettings()
    ) {
        self.version = Self.currentVersion
        self.computers = computers
        self.jobs = jobs
        self.statuses = statuses
        self.settings = settings
    }

    public func computer(for job: SyncJob) -> Computer? {
        computers.first { $0.id == job.computerID }
    }

    public func status(for job: SyncJob) -> JobStatus {
        statuses[job.id] ?? JobStatus()
    }

    /// Entfernt einen Computer samt seiner Jobs und Status.
    public mutating func removeComputer(id: UUID) {
        let jobIDs = jobs.filter { $0.computerID == id }.map(\.id)
        jobs.removeAll { $0.computerID == id }
        jobIDs.forEach { statuses[$0] = nil }
        computers.removeAll { $0.id == id }
    }

    public mutating func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        statuses[id] = nil
    }
}
