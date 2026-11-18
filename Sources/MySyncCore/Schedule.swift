import Foundation

/// Wann ein Ordner synchronisiert wird.
public enum Schedule: Codable, Hashable, Sendable {
    case everyMinutes(Int)
    case hourly
    case daily(hour: Int, minute: Int)
    /// Nie automatisch, nur per Klick im Menü.
    case manual

    /// Kurzbeschreibung für Menü und Einstellungen, z. B. „täglich um 12:00 Uhr“.
    public var description: String {
        switch self {
        case .everyMinutes(let minutes):
            let m = max(1, minutes)
            return m == 1 ? "jede Minute" : "alle \(m) Minuten"
        case .hourly:
            return "stündlich"
        case .daily(let hour, let minute):
            return String(format: "täglich um %02d:%02d Uhr", hour, minute)
        case .manual:
            return "nur manuell"
        }
    }

    /// Der nächste Zeitpunkt, zu dem nach `last` synchronisiert werden soll.
    /// Ohne bisherigen Versuch ist der Job sofort fällig.
    public func nextRun(after last: Date?, calendar: Calendar = .current) -> Date {
        if case .manual = self { return .distantFuture }
        guard let last else { return .distantPast }
        switch self {
        case .manual:
            return .distantFuture
        case .everyMinutes(let minutes):
            return last.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        case .hourly:
            return last.addingTimeInterval(3600)
        case .daily(let hour, let minute):
            let components = DateComponents(hour: hour, minute: minute, second: 0)
            return calendar.nextDate(
                after: last,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) ?? last.addingTimeInterval(86_400)
        }
    }

    /// Ist der Job zum Zeitpunkt `now` fällig?
    public func isDue(lastAttempt: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        now >= nextRun(after: lastAttempt, calendar: calendar)
    }
}

/// Bearbeitbare Form eines Intervalls für die Einstellungs-UI.
public enum ScheduleKind: String, CaseIterable, Identifiable, Sendable {
    case minutes, hourly, daily, manual
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .minutes: return "Alle X Minuten"
        case .hourly: return "Stündlich"
        case .daily: return "Täglich"
        case .manual: return "Nur manuell"
        }
    }
}

public extension Schedule {
    var kind: ScheduleKind {
        switch self {
        case .everyMinutes: return .minutes
        case .hourly: return .hourly
        case .daily: return .daily
        case .manual: return .manual
        }
    }
}
