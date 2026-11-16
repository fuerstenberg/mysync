import AppKit
import CoreLocation
import ServiceManagement
import UserNotifications
import MySyncCore

/// Systembenachrichtigungen.
struct UserNotifier: Notifying {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Die Ortungsfreigabe wird von macOS benötigt, um den WLAN-Namen (SSID) auszulesen.
@MainActor
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedAlways || status == .authorized
    }

    var label: String {
        switch status {
        case .authorizedAlways, .authorized: return "erteilt"
        case .denied: return "abgelehnt"
        case .restricted: return "eingeschränkt"
        case .notDetermined: return "noch nicht angefragt"
        @unknown default: return "unbekannt"
        }
    }

    func request() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in self.status = newStatus }
    }
}

/// Start beim Anmelden über SMAppService.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
