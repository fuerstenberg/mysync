import Foundation

/// Baut die Argumentliste für einen rsync-Aufruf.
/// Es werden nur Optionen verwendet, die sowohl openrsync (macOS) als auch GNU rsync verstehen.
public struct RsyncCommandBuilder: Sendable {
    public var sshPath: String
    /// GNU rsync ab 3.2.4 maskiert entfernte Pfade selbst. Dann darf mysync nicht zusätzlich maskieren.
    public var rsyncEscapesRemotePaths: Bool

    public init(sshPath: String = "/usr/bin/ssh", rsyncEscapesRemotePaths: Bool = false) {
        self.sshPath = sshPath
        self.rsyncEscapesRemotePaths = rsyncEscapesRemotePaths
    }

    /// Ordner bekommen einen abschließenden Slash, damit rsync den *Inhalt* kopiert
    /// und keinen zusätzlichen Unterordner anlegt.
    public static func withTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// Expandiert `~` in lokalen Pfaden.
    public static func expandLocal(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Die `-e`-Option für die SSH-Verbindung.
    public func sshCommand(for computer: Computer, connectTimeout: Int = 10) -> String {
        var parts = [
            sshPath,
            "-p", String(computer.port),
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        let key = computer.sshKeyPath.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            parts += ["-i", Self.shellQuote(Self.expandLocal(key))]
        }
        return parts.joined(separator: " ")
    }

    /// Argumente für `ssh`, um die Anmeldung ohne Passwort zu testen (für „Verbindung testen“).
    public func sshTestArguments(for computer: Computer, connectTimeout: Int = 5) -> [String] {
        var args = [
            "-p", String(computer.port),
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        let key = computer.sshKeyPath.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            args += ["-i", Self.expandLocal(key)]
        }
        args += [computer.sshDestination, "echo mysync-ok"]
        return args
    }

    /// Gemeinsame Optionen für jeden Lauf.
    public func baseOptions(for job: SyncJob) -> [String] {
        var args = ["-az", "--partial"]
        if job.effectiveDeleteExtraneous {
            args.append("--delete")
        }
        if job.removeSourceFiles {
            args.append("--remove-source-files")
        }
        for pattern in job.excludes where !pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append("--exclude=\(pattern)")
        }
        return args
    }

    /// Argumente für eine Synchronisierung über SSH.
    public func arguments(for job: SyncJob, computer: Computer) -> [String] {
        var args = baseOptions(for: job)
        args += ["-e", sshCommand(for: computer)]

        let local = Self.withTrailingSlash(Self.expandLocal(job.localPath))
        let remotePath = rsyncEscapesRemotePaths
            ? Self.withTrailingSlash(job.remotePath.trimmingCharacters(in: .whitespaces))
            : Self.remotePathArgument(job.remotePath)
        let remote = "\(computer.sshDestination):\(remotePath)"

        switch job.direction {
        case .push:
            args += [local, remote]
        case .pull:
            args += [remote, local]
        }
        return args
    }

    /// Argumente für eine rein lokale Synchronisierung (z. B. für Tests oder externe Laufwerke).
    public func localArguments(for job: SyncJob, destination: String) -> [String] {
        var args = baseOptions(for: job)
        let source = Self.withTrailingSlash(Self.expandLocal(job.localPath))
        let dest = Self.withTrailingSlash(Self.expandLocal(destination))
        switch job.direction {
        case .push: args += [source, dest]
        case .pull: args += [dest, source]
        }
        return args
    }

    /// Der entfernte Pfad wird von der Remote-Shell interpretiert.
    /// Leerzeichen und Sonderzeichen werden deshalb maskiert; ein führendes `~/` bleibt erhalten.
    public static func remotePathArgument(_ path: String) -> String {
        var p = withTrailingSlash(path.trimmingCharacters(in: .whitespaces))
        var prefix = ""
        if p.hasPrefix("~/") {
            prefix = "~/"
            p.removeFirst(2)
        }
        return prefix + escapeForRemoteShell(p)
    }

    static func escapeForRemoteShell(_ s: String) -> String {
        let special = Set(" \t'\"\\$`!&;|<>()[]{}*?#")
        var out = ""
        for ch in s {
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Quoting für Argumente innerhalb der `-e`-Zeichenkette.
    static func shellQuote(_ s: String) -> String {
        if s.rangeOfCharacter(from: CharacterSet(charactersIn: " '\"\\$`")) == nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Findet das zu verwendende rsync-Programm.
public enum RsyncLocator {
    public static let candidates = [
        "/opt/homebrew/bin/rsync",
        "/usr/local/bin/rsync",
        "/usr/bin/rsync"
    ]

    public static func locate(
        customPath: String,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let custom = customPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            return fileExists(expanded) ? expanded : nil
        }
        return candidates.first(where: fileExists)
    }
}

/// Welche rsync-Variante installiert ist.
public enum RsyncFlavor: Equatable, Sendable {
    case openrsync
    case gnu(major: Int, minor: Int, patch: Int)
    case unknown

    /// Wertet die Ausgabe von `rsync --version` aus.
    public static func parse(versionOutput: String) -> RsyncFlavor {
        let lower = versionOutput.lowercased()
        if lower.contains("openrsync") { return .openrsync }
        // „rsync  version 3.2.7  protocol version 31“
        let pattern = #"rsync\s+version\s+v?(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              match.numberOfRanges == 4 else { return .unknown }
        func int(_ i: Int) -> Int {
            Range(match.range(at: i), in: lower).flatMap { Int(lower[$0]) } ?? 0
        }
        return .gnu(major: int(1), minor: int(2), patch: int(3))
    }

    /// GNU rsync ab 3.2.4 maskiert entfernte Argumente automatisch.
    public var escapesRemotePaths: Bool {
        if case let .gnu(major, minor, patch) = self {
            return (major, minor, patch) >= (3, 2, 4)
        }
        return false
    }

    public var label: String {
        switch self {
        case .openrsync: return "openrsync (macOS)"
        case let .gnu(a, b, c): return "rsync \(a).\(b).\(c)"
        case .unknown: return "unbekannt"
        }
    }
}
