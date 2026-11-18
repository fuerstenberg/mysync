import Foundation

/// Übernimmt ein Ergebnis in den Status und entscheidet, ob eine Benachrichtigung nötig ist.
public enum NotificationPolicy {
    public struct Decision: Equatable, Sendable {
        public var status: JobStatus
        public var shouldNotify: Bool
    }

    public static func apply(result: SyncResult, to previous: JobStatus, at now: Date) -> Decision {
        var status = previous
        status.lastAttempt = now
        status.lastOutcome = result.outcome
        status.lastMessage = result.message

        switch result.outcome {
        case .success:
            status.lastSuccess = now
            status.notifiedForCurrentFailure = false
            return Decision(status: status, shouldNotify: false)
        case .skippedNotInNetwork:
            // Nicht zu Hause o. ä.: still bleiben.
            return Decision(status: status, shouldNotify: false)
        case .failed, .unreachable:
            let notify = !previous.notifiedForCurrentFailure
            status.notifiedForCurrentFailure = true
            return Decision(status: status, shouldNotify: notify)
        }
    }
}

/// Farbe des Punktes am Statusmenü-Icon.
public enum StatusIndicator: Equatable, Sendable {
    case none
    case ok
    case error
}

public enum StatusAggregator {
    public static func indicator(for config: AppConfig) -> StatusIndicator {
        var anySuccess = false
        for job in config.jobs where job.enabled {
            switch config.statuses[job.id]?.lastOutcome {
            case .failed?, .unreachable?:
                return .error
            case .success?:
                anySuccess = true
            case .skippedNotInNetwork?, nil:
                continue
            }
        }
        return anySuccess ? .ok : .none
    }
}

/// Bestimmt, welche Jobs jetzt laufen sollen.
public enum Scheduler {
    /// Nach einem Ausfall oder außerhalb des Netzwerks wird spätestens nach dieser Zeit erneut versucht,
    /// damit z. B. ein täglicher Sync nach dem Heimkommen nachgeholt wird.
    public static let retryInterval: TimeInterval = 5 * 60

    public static func nextRun(for job: SyncJob, status: JobStatus, calendar: Calendar = .current) -> Date {
        // Manuelle Ordner laufen nie von selbst, auch nicht als Wiederholung nach einem Fehler.
        if case .manual = job.schedule { return .distantFuture }
        let regular = job.schedule.nextRun(after: status.lastAttempt, calendar: calendar)
        guard let last = status.lastAttempt,
              let outcome = status.lastOutcome,
              outcome != .success else {
            return regular
        }
        return min(regular, last.addingTimeInterval(retryInterval))
    }

    public static func dueJobs(
        in config: AppConfig,
        now: Date,
        running: Set<UUID>,
        calendar: Calendar = .current
    ) -> [SyncJob] {
        config.jobs.filter { job in
            job.enabled
                && !running.contains(job.id)
                && config.computer(for: job) != nil
                && now >= nextRun(for: job, status: config.status(for: job), calendar: calendar)
        }
    }
}
