import Foundation
import Combine

public protocol Notifying: Sendable {
    func notify(title: String, body: String)
}

public struct SilentNotifier: Notifying {
    public init() {}
    public func notify(title: String, body: String) {}
}

/// Hält die Konfiguration, startet fällige Synchronisierungen und meldet Fehler.
@MainActor
public final class SyncCoordinator: ObservableObject {
    @Published public private(set) var config: AppConfig
    @Published public private(set) var running: Set<UUID> = []
    @Published public private(set) var lastError: String?

    private let store: ConfigStoring
    private let engine: SyncPerforming
    private let notifier: Notifying
    private let clock: @Sendable () -> Date
    private var timer: Timer?

    public init(
        store: ConfigStoring,
        engine: SyncPerforming,
        notifier: Notifying,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.engine = engine
        self.notifier = notifier
        self.clock = clock
        do {
            self.config = try store.load()
        } catch {
            self.config = AppConfig()
            self.lastError = "Konfiguration konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    public var indicator: StatusIndicator { StatusAggregator.indicator(for: config) }

    // MARK: - Zeitsteuerung

    public func start(interval: TimeInterval = 30) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Startet alle fälligen Jobs und wartet, bis sie fertig sind.
    public func tick() async {
        let due = Scheduler.dueJobs(in: config, now: clock(), running: running)
        await withTaskGroup(of: Void.self) { group in
            for job in due {
                group.addTask { await self.sync(jobID: job.id) }
            }
        }
    }

    // MARK: - Synchronisieren

    /// Synchronisiert einen Job sofort (z. B. nach Klick im Menü).
    public func sync(jobID: UUID) async {
        guard !running.contains(jobID),
              let job = config.jobs.first(where: { $0.id == jobID }),
              let computer = config.computer(for: job) else { return }

        running.insert(jobID)
        let result = await engine.perform(job: job, computer: computer, settings: config.settings)
        running.remove(jobID)

        // Der Job könnte inzwischen gelöscht worden sein.
        guard config.jobs.contains(where: { $0.id == jobID }) else { return }

        let decision = NotificationPolicy.apply(result: result, to: config.status(for: job), at: clock())
        config.statuses[jobID] = decision.status
        persist()

        if decision.shouldNotify {
            let title = result.outcome == .unreachable
                ? "\(computer.displayName) nicht erreichbar"
                : "Synchronisierung fehlgeschlagen"
            let body = "\(job.folderName): \(result.message ?? "Unbekannter Fehler")"
            notifier.notify(title: title, body: body)
        }
    }

    public func syncAll() async {
        await withTaskGroup(of: Void.self) { group in
            for job in config.jobs where job.enabled {
                group.addTask { await self.sync(jobID: job.id) }
            }
        }
    }

    // MARK: - Bearbeiten

    public func update(_ change: (inout AppConfig) -> Void) {
        change(&config)
        persist()
    }

    public func upsert(computer: Computer) {
        update { config in
            if let i = config.computers.firstIndex(where: { $0.id == computer.id }) {
                config.computers[i] = computer
            } else {
                config.computers.append(computer)
            }
        }
    }

    public func upsert(job: SyncJob) {
        update { config in
            if let i = config.jobs.firstIndex(where: { $0.id == job.id }) {
                // Bei geändertem Ziel oder Intervall den alten Status verwerfen.
                let old = config.jobs[i]
                if old.computerID != job.computerID || old.remotePath != job.remotePath
                    || old.localPath != job.localPath || old.direction != job.direction {
                    config.statuses[job.id] = nil
                }
                config.jobs[i] = job
            } else {
                config.jobs.append(job)
            }
        }
    }

    public func removeComputer(id: UUID) {
        update { $0.removeComputer(id: id) }
    }

    public func removeJob(id: UUID) {
        update { $0.removeJob(id: id) }
    }

    public func updateSettings(_ settings: AppSettings) {
        update { $0.settings = settings }
    }

    private func persist() {
        do {
            try store.save(config)
            lastError = nil
        } catch {
            lastError = "Konfiguration konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
