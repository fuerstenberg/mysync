import Foundation

/// Prüft, ob die SSH-Anmeldung an einem Computer ohne Passwort funktioniert.
public struct ConnectionTester: Sendable {
    public enum Outcome: Equatable, Sendable {
        case success
        case failure(String)

        public var message: String {
            switch self {
            case .success: return "Verbindung erfolgreich – die Anmeldung per SSH-Schlüssel funktioniert."
            case .failure(let text): return text
            }
        }
    }

    public var runner: ProcessRunning
    public var sshPath: String

    public init(runner: ProcessRunning = ProcessRunner(), sshPath: String = "/usr/bin/ssh") {
        self.runner = runner
        self.sshPath = sshPath
    }

    public func test(_ computer: Computer) async -> Outcome {
        if computer.host.trimmingCharacters(in: .whitespaces).isEmpty {
            return .failure("Bitte zuerst einen Host angeben.")
        }
        let args = RsyncCommandBuilder(sshPath: sshPath).sshTestArguments(for: computer)
        do {
            let result = try await runner.run(executable: sshPath, arguments: args, timeout: 15)
            return Self.interpret(result)
        } catch {
            return .failure("ssh konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    public static func interpret(_ result: ProcessResult) -> Outcome {
        if result.succeeded && result.stdout.contains("mysync-ok") { return .success }
        if result.timedOut { return .failure("Zeitüberschreitung – der Computer antwortet nicht.") }
        let err = result.stderr
        if err.contains("Permission denied") {
            return .failure("Anmeldung abgelehnt. Ist Ihr öffentlicher SSH-Schlüssel auf dem Computer hinterlegt (ssh-copy-id)?")
        }
        if err.contains("Could not resolve hostname") {
            return .failure("Der Host-Name konnte nicht aufgelöst werden.")
        }
        if err.contains("Connection refused") {
            return .failure("Verbindung abgelehnt. Ist auf dem Computer „Entfernte Anmeldung“ (SSH) aktiv?")
        }
        if err.contains("timed out") || err.contains("No route to host") {
            return .failure("Der Computer ist nicht erreichbar.")
        }
        if err.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            return .failure("Der Host-Schlüssel hat sich geändert. Bitte ~/.ssh/known_hosts prüfen.")
        }
        let line = err.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Code \(result.exitCode)"
        return .failure("Verbindung fehlgeschlagen: \(line)")
    }
}
