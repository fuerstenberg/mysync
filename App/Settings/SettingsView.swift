import AppKit
import SwiftUI
import MySyncCore

/// Fenster für die Einstellungen (Statusmenü-Apps haben kein Hauptfenster).
@MainActor
final class SettingsWindowController {
    private let coordinator: SyncCoordinator
    private let location: LocationPermission
    private var window: NSWindow?

    init(coordinator: SyncCoordinator, location: LocationPermission) {
        self.coordinator = coordinator
        self.location = location
    }

    func show() {
        if window == nil {
            let view = SettingsView()
                .environmentObject(coordinator)
                .environmentObject(location)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "mysync – Einstellungen"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 460))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            JobsTab()
                .tabItem { Label("Ordner", systemImage: "folder") }
            ComputersTab()
                .tabItem { Label("Computer", systemImage: "desktopcomputer") }
            GeneralTab()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
    }
}

// MARK: - Computer

struct ComputersTab: View {
    @EnvironmentObject var coordinator: SyncCoordinator
    @State private var editing: Computer?
    @State private var confirmDelete: Computer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Computer, mit denen per SSH synchronisiert wird.")
                .foregroundStyle(.secondary)

            List {
                ForEach(coordinator.config.computers) { computer in
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading) {
                            Text(computer.displayName).font(.headline)
                            Text("\(computer.sshDestination):\(computer.port)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(networkSummary(computer)).font(.caption).foregroundStyle(.secondary)
                        Button("Bearbeiten") { editing = computer }
                        Button(role: .destructive) { confirmDelete = computer } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = computer }
                }
            }
            .overlay {
                if coordinator.config.computers.isEmpty {
                    Text("Noch kein Computer angelegt.").foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button {
                    editing = Computer()
                } label: {
                    Label("Computer hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { computer in
            ComputerEditor(draft: computer) { saved in
                coordinator.upsert(computer: saved)
            }
        }
        .confirmationDialog(
            "„\(confirmDelete?.displayName ?? "")“ entfernen?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("Entfernen", role: .destructive) {
                if let c = confirmDelete { coordinator.removeComputer(id: c.id) }
            }
        } message: {
            Text("Alle Ordner dieses Computers werden ebenfalls aus mysync entfernt. Dateien werden nicht gelöscht.")
        }
    }

    private func networkSummary(_ c: Computer) -> String {
        let parts = c.ssids + c.subnets
        return parts.isEmpty ? "jedes Netzwerk" : parts.joined(separator: ", ")
    }
}

// MARK: - Ordner

struct JobsTab: View {
    @EnvironmentObject var coordinator: SyncCoordinator
    @State private var editing: SyncJob?
    @State private var confirmDelete: SyncJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ordnerpaare, die per rsync synchronisiert werden.")
                .foregroundStyle(.secondary)

            List {
                ForEach(coordinator.config.jobs) { job in
                    let computer = coordinator.config.computer(for: job)
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { job.enabled },
                            set: { newValue in
                                var j = job; j.enabled = newValue
                                coordinator.upsert(job: j)
                            }
                        ))
                        .labelsHidden()
                        .help("Aktiv")
                        VStack(alignment: .leading) {
                            Text("\(computer?.displayName ?? "?") \(job.direction.arrow) \(job.folderName)")
                                .font(.headline)
                            Text("\(job.localPath)  \(job.direction.arrow)  \(job.remotePath)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(job.schedule.description).font(.caption).foregroundStyle(.secondary)
                        Button("Bearbeiten") { editing = job }
                        Button(role: .destructive) { confirmDelete = job } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = job }
                }
            }
            .overlay {
                if coordinator.config.jobs.isEmpty {
                    Text(coordinator.config.computers.isEmpty
                         ? "Legen Sie zuerst unter „Computer“ einen Computer an."
                         : "Noch kein Ordner eingerichtet.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button {
                    if let first = coordinator.config.computers.first {
                        editing = SyncJob(computerID: first.id)
                    }
                } label: {
                    Label("Ordner hinzufügen", systemImage: "plus")
                }
                .disabled(coordinator.config.computers.isEmpty)
            }
        }
        .sheet(item: $editing) { job in
            JobEditor(draft: job, computers: coordinator.config.computers) { saved in
                coordinator.upsert(job: saved)
            }
        }
        .confirmationDialog(
            "„\(confirmDelete?.folderName ?? "")“ entfernen?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("Entfernen", role: .destructive) {
                if let j = confirmDelete { coordinator.removeJob(id: j.id) }
            }
        } message: {
            Text("Nur die Einrichtung wird entfernt. Dateien bleiben unverändert.")
        }
    }
}

// MARK: - Allgemein

struct GeneralTab: View {
    @EnvironmentObject var coordinator: SyncCoordinator
    @EnvironmentObject var location: LocationPermission
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var rsyncPath = ""
    @State private var rsyncInfo = ""

    var body: some View {
        Form {
            Section("Start") {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LaunchAtLogin.set(newValue)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("rsync") {
                HStack {
                    TextField("Pfad (leer = automatisch)", text: $rsyncPath)
                        .onSubmit(saveRsyncPath)
                    Button("Übernehmen", action: saveRsyncPath)
                }
                Text(rsyncInfo).font(.caption).foregroundStyle(.secondary)
            }

            Section("Netzwerkerkennung") {
                HStack {
                    Text("Ortungsfreigabe: \(location.label)")
                    Spacer()
                    if !location.isAuthorized {
                        Button("Freigeben …") { location.request() }
                    }
                }
                Text("macOS gibt den WLAN-Namen nur mit Ortungsfreigabe heraus. Ohne Freigabe erkennt mysync Ihr Netzwerk nur über das Subnetz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rsyncPath = coordinator.config.settings.rsyncPath
            updateRsyncInfo()
        }
    }

    private func saveRsyncPath() {
        var settings = coordinator.config.settings
        settings.rsyncPath = rsyncPath.trimmingCharacters(in: .whitespaces)
        coordinator.updateSettings(settings)
        updateRsyncInfo()
    }

    private func updateRsyncInfo() {
        guard let path = RsyncLocator.locate(customPath: rsyncPath) else {
            rsyncInfo = "⚠︎ Kein rsync gefunden."
            return
        }
        rsyncInfo = "Verwendet: \(path)"
        Task {
            let result = try? await ProcessRunner().run(executable: path, arguments: ["--version"], timeout: 5)
            let flavor = RsyncFlavor.parse(versionOutput: (result?.stdout ?? "") + (result?.stderr ?? ""))
            var info = "Verwendet: \(path) – \(flavor.label)"
            if flavor == .openrsync {
                info += ". Tipp: „brew install rsync“ installiert das vollständige GNU rsync."
            }
            rsyncInfo = info
        }
    }
}
