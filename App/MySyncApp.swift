import AppKit
import MySyncCore

@main
enum MySyncMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SyncCoordinator!
    private var statusController: StatusItemController!
    private var settingsController: SettingsWindowController!
    private let location = LocationPermission()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notifier = UserNotifier()
        notifier.requestAuthorization()

        coordinator = SyncCoordinator(
            store: ConfigStore.default,
            engine: SyncEngine(),
            notifier: notifier
        )
        settingsController = SettingsWindowController(coordinator: coordinator, location: location)
        statusController = StatusItemController(coordinator: coordinator) { [weak self] in
            self?.settingsController.show()
        }

        coordinator.start()

        // Nach dem Aufwachen sofort prüfen, ob etwas fällig ist.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Dem Netzwerk ein paar Sekunden zum Verbinden geben.
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self?.coordinator.tick()
            }
        }

        // Beim ersten Start direkt die Einstellungen zeigen.
        if coordinator.config.computers.isEmpty {
            settingsController.show()
        }
    }
}
