import Foundation

/// Deutsche Texte für das Menü.
public enum SyncFormatting {
    /// „gerade eben“, „vor 5 Min.“, „vor 3 Std.“, „gestern 12:00“, „14.11. 08:30“
    public static func relative(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "noch nie" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "gerade eben" }
        if seconds < 3600 { return "vor \(Int(seconds / 60)) Min." }
        if calendar.isDate(date, inSameDayAs: now) {
            return "heute \(time(date, calendar: calendar))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern \(time(date, calendar: calendar))"
        }
        let c = calendar.dateComponents([.day, .month], from: date)
        return String(format: "%02d.%02d. %@", c.day ?? 0, c.month ?? 0, time(date, calendar: calendar))
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Zweite Zeile eines Menüeintrags, z. B. „✓ zuletzt heute 12:00“.
    public static func statusLine(_ status: JobStatus, isRunning: Bool, now: Date, calendar: Calendar = .current) -> String {
        if isRunning { return "⟳ wird synchronisiert …" }
        let last = relative(status.lastSuccess, now: now, calendar: calendar)
        switch status.lastOutcome {
        case nil:
            return "noch nicht synchronisiert"
        case .success?:
            return "✓ zuletzt \(last)"
        case .failed?:
            return "✗ Fehler – zuletzt erfolgreich: \(last)"
        case .unreachable?:
            return "✗ nicht erreichbar – zuletzt erfolgreich: \(last)"
        case .skippedNotInNetwork?:
            return "– nicht im Netzwerk – zuletzt erfolgreich: \(last)"
        }
    }
}
