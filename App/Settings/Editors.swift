import AppKit
import SwiftUI
import MySyncCore

// MARK: - Computer bearbeiten

struct ComputerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var location: LocationPermission
    @State var draft: Computer
    let onSave: (Computer) -> Void

    @State private var testing = false
    @State private var testResult: ConnectionTester.Outcome?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Verbindung") {
                    TextField("Name", text: $draft.name, prompt: Text("z. B. NAS im Keller"))
                    TextField("Host", text: $draft.host, prompt: Text("nas.local oder 192.168.1.20"))
                    TextField("Benutzer", text: $draft.user)
                    TextField("Port", value: $draft.port, format: .number.grouping(.never))
                    HStack {
                        TextField("SSH-Schlüssel", text: $draft.sshKeyPath, prompt: Text("Standard aus ~/.ssh"))
                        Button("Auswählen …", action: chooseKey)
                    }
                    HStack {
                        Button(testing ? "Teste …" : "Verbindung testen", action: runTest)
                            .disabled(testing || draft.host.isEmpty)
                        if testing { ProgressView().controlSize(.small) }
                    }
                    if let testResult {
                        Label(testResult.message,
                              systemImage: testResult == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testResult == .success ? .green : .red)
                            .font(.callout)
                    }
                }

                Section {
                    StringListEditor(items: $draft.ssids, placeholder: "WLAN-Name")
                    Button("Aktuelles WLAN übernehmen", action: addCurrentSSID)
                } header: {
                    Text("Heimnetz – WLAN-Namen")
                }

                Section {
                    StringListEditor(items: $draft.subnets, placeholder: "z. B. 192.168.1.0/24")
                    Button("Aktuelles Subnetz übernehmen", action: addCurrentSubnet)
                } header: {
                    Text("Heimnetz – Subnetze (z. B. für LAN-Kabel)")
                } footer: {
                    Text("Ist der Computer nicht erreichbar, meldet mysync das nur, wenn Sie in einem dieser Netze sind. Ohne Angaben wird jeder Ausfall gemeldet.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    onSave(cleaned)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.host.trimmingCharacters(in: .whitespaces).isEmpty || !(1...65535).contains(draft.port))
            }
            .padding()
        }
        .frame(width: 520, height: 620)
    }

    private var cleaned: Computer {
        var c = draft
        c.host = c.host.trimmingCharacters(in: .whitespaces)
        c.user = c.user.trimmingCharacters(in: .whitespaces)
        c.ssids = c.ssids.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.subnets = c.subnets.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return c
    }

    private func runTest() {
        testing = true
        testResult = nil
        let computer = cleaned
        Task {
            let result = await ConnectionTester().test(computer)
            testResult = result
            testing = false
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        panel.message = "Privaten SSH-Schlüssel auswählen (nicht die .pub-Datei)"
        if panel.runModal() == .OK, let url = panel.url {
            draft.sshKeyPath = url.path
        }
    }

    private func addCurrentSSID() {
        if let ssid = SystemNetworkInfoProvider.currentSSID() {
            if !draft.ssids.contains(ssid) { draft.ssids.append(ssid) }
            hint = nil
        } else if !location.isAuthorized {
            hint = "Für den WLAN-Namen braucht mysync die Ortungsfreigabe."
            location.request()
        } else {
            hint = "Sie sind gerade mit keinem WLAN verbunden."
        }
    }

    private func addCurrentSubnet() {
        let subnets = SystemNetworkInfoProvider.ipv4Interfaces().map(\.cidr)
        guard !subnets.isEmpty else {
            hint = "Keine aktive Netzwerkverbindung gefunden."
            return
        }
        for s in subnets where !draft.subnets.contains(s) {
            draft.subnets.append(s)
        }
        hint = nil
    }
}

// MARK: - Ordner bearbeiten

struct JobEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: SyncJob
    let computers: [Computer]
    let onSave: (SyncJob) -> Void

    @State private var kind: ScheduleKind = .hourly
    @State private var minutes = 30
    @State private var dailyTime = Calendar.current.date(from: DateComponents(hour: 12, minute: 0)) ?? Date()

    init(draft: SyncJob, computers: [Computer], onSave: @escaping (SyncJob) -> Void) {
        _draft = State(initialValue: draft)
        self.computers = computers
        self.onSave = onSave
        _kind = State(initialValue: draft.schedule.kind)
        switch draft.schedule {
        case .everyMinutes(let m):
            _minutes = State(initialValue: m)
        case .daily(let h, let m):
            _dailyTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: h, minute: m)) ?? Date())
        case .hourly:
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Ordner") {
                    Picker("Computer", selection: $draft.computerID) {
                        ForEach(computers) { c in
                            Text(c.displayName).tag(c.id)
                        }
                    }
                    HStack {
                        TextField("Lokaler Ordner", text: $draft.localPath, prompt: Text("~/Dokumente"))
                        Button("Auswählen …", action: chooseFolder)
                    }
                    TextField("Ordner auf dem Computer", text: $draft.remotePath, prompt: Text("/volume1/backup/Dokumente"))
                    Picker("Richtung", selection: $draft.direction) {
                        ForEach(SyncDirection.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Intervall") {
                    Picker("Synchronisieren", selection: $kind) {
                        ForEach(ScheduleKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    switch kind {
                    case .minutes:
                        Stepper(value: $minutes, in: 1...1440, step: minutes < 10 ? 1 : 5) {
                            HStack {
                                Text("Alle")
                                TextField("", value: $minutes, format: .number)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("Minuten")
                            }
                        }
                    case .hourly:
                        EmptyView()
                    case .daily:
                        DatePicker("Uhrzeit", selection: $dailyTime, displayedComponents: .hourAndMinute)
                    }
                    Text("Anzeige im Menü: \(schedule.description)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Optionen") {
                    Toggle("Aktiv", isOn: $draft.enabled)
                    Toggle("Im Ziel löschen, was in der Quelle fehlt (--delete)", isOn: $draft.deleteExtraneous)
                    if draft.deleteExtraneous {
                        Label("Vorsicht: Dateien im Ziel, die in der Quelle nicht (mehr) vorhanden sind, werden gelöscht.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading) {
                        Text("Ausschließen")
                        StringListEditor(items: $draft.excludes, placeholder: "z. B. *.tmp oder node_modules/")
                    }
                }

                Section("rsync-Aufruf (Vorschau)") {
                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    var job = draft
                    job.schedule = schedule
                    job.localPath = job.localPath.trimmingCharacters(in: .whitespaces)
                    job.remotePath = job.remotePath.trimmingCharacters(in: .whitespaces)
                    job.excludes = job.excludes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    onSave(job)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.localPath.trimmingCharacters(in: .whitespaces).isEmpty
                          || draft.remotePath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 680)
    }

    private var schedule: Schedule {
        switch kind {
        case .minutes:
            return .everyMinutes(max(1, minutes))
        case .hourly:
            return .hourly
        case .daily:
            let c = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            return .daily(hour: c.hour ?? 12, minute: c.minute ?? 0)
        }
    }

    private var commandPreview: String {
        guard let computer = computers.first(where: { $0.id == draft.computerID }) else { return "" }
        let args = RsyncCommandBuilder().arguments(for: draft, computer: computer)
        return "rsync " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Lokalen Ordner auswählen"
        if panel.runModal() == .OK, let url = panel.url {
            draft.localPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: .anchored)
        }
    }
}

// MARK: - Liste von Texten

struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField(placeholder, text: Binding(
                        get: { index < items.count ? items[index] : "" },
                        set: { if index < items.count { items[index] = $0 } }
                    ))
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField(placeholder, text: $newItem)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let value = newItem.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !items.contains(value) else { return }
        items.append(value)
        newItem = ""
    }
}
