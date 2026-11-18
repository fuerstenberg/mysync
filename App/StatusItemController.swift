import AppKit
import Combine
import MySyncCore

/// Das Symbol im Statusmenü samt Dropdown.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: SyncCoordinator
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let dot = StatusDotView()
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: SyncCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "mysync")
            image?.isTemplate = true
            button.image = image
            button.addSubview(dot)
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
                dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
                dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3)
            ])
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        coordinator.$config
            .combineLatest(coordinator.$running)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    // MARK: - Aktualisieren

    private func refresh() {
        dot.indicator = coordinator.indicator
        statusItem.button?.toolTip = tooltip
        rebuildMenu()
    }

    private var tooltip: String {
        switch coordinator.indicator {
        case .ok: return "mysync – alle Ordner synchronisiert"
        case .error: return "mysync – nicht alle Ordner synchronisiert"
        case .none: return "mysync"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Relative Zeiten („vor 5 Min.“) frisch berechnen.
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let config = coordinator.config
        let now = Date()

        if config.jobs.isEmpty {
            let empty = NSMenuItem(title: "Noch keine Ordner eingerichtet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Klicken zum Synchronisieren", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for job in config.jobs {
                guard let computer = config.computer(for: job) else { continue }
                menu.addItem(item(for: job, computer: computer, status: config.status(for: job), now: now))
            }

            menu.addItem(.separator())
            let all = NSMenuItem(title: "Alle jetzt synchronisieren", action: #selector(syncAll), keyEquivalent: "s")
            all.target = self
            all.isEnabled = config.jobs.contains { $0.enabled }
            menu.addItem(all)
        }

        if let error = coordinator.lastError {
            let item = NSMenuItem(title: "⚠︎ \(error)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func item(for job: SyncJob, computer: Computer, status: JobStatus, now: Date) -> NSMenuItem {
        let isRunning = coordinator.running.contains(job.id)
        let item = NSMenuItem(title: "", action: #selector(syncJob(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = job.id
        item.isEnabled = !isRunning
        item.attributedTitle = MenuRowFormatter.title(
            job: job, computer: computer, status: status, isRunning: isRunning, now: now
        )
        item.image = MenuRowFormatter.icon(for: status, enabled: job.enabled, isRunning: isRunning)
        if let message = status.lastMessage, status.lastOutcome != .success {
            item.toolTip = message
        }
        return item
    }

    // MARK: - Aktionen

    @objc private func syncJob(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        Task { await coordinator.sync(jobID: id) }
    }

    @objc private func syncAll() {
        Task { await coordinator.syncAll() }
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Der kleine farbige Punkt am Symbol.
final class StatusDotView: NSView {
    var indicator: StatusIndicator = .none {
        didSet { needsDisplay = true; isHidden = indicator == .none }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = indicator == .error ? .systemRed : .systemGreen
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Baut die zweizeiligen Menüeinträge.
enum MenuRowFormatter {
    static let width: CGFloat = 360

    static func title(job: SyncJob, computer: Computer, status: JobStatus, isRunning: Bool, now: Date) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: width)]
        paragraph.lineBreakMode = .byTruncatingMiddle

        let result = NSMutableAttributedString()
        let primary = job.enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor
        result.append(NSAttributedString(
            string: "\(computer.displayName) \(job.arrow) \(job.folderName)",
            attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: primary, .paragraphStyle: paragraph]
        ))
        let interval = job.enabled ? job.schedule.description : "pausiert"
        result.append(NSAttributedString(
            string: "\t\(interval)",
            attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        ))
        let line2 = SyncFormatting.statusLine(status, isRunning: isRunning, now: now)
        result.append(NSAttributedString(
            string: "\n\(line2)",
            attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: secondaryColor(for: status, isRunning: isRunning), .paragraphStyle: paragraph]
        ))
        return result
    }

    static func secondaryColor(for status: JobStatus, isRunning: Bool) -> NSColor {
        if isRunning { return .secondaryLabelColor }
        switch status.lastOutcome {
        case .failed?, .unreachable?: return .systemRed
        default: return .secondaryLabelColor
        }
    }

    static func icon(for status: JobStatus, enabled: Bool, isRunning: Bool) -> NSImage? {
        let name: String
        let color: NSColor
        if isRunning {
            name = "arrow.triangle.2.circlepath"; color = .systemBlue
        } else if !enabled {
            name = "pause.circle"; color = .tertiaryLabelColor
        } else {
            switch status.lastOutcome {
            case .success?: name = "checkmark.circle.fill"; color = .systemGreen
            case .failed?, .unreachable?: name = "exclamationmark.circle.fill"; color = .systemRed
            case .skippedNotInNetwork?: name = "wifi.slash"; color = .secondaryLabelColor
            case nil: name = "circle.dashed"; color = .secondaryLabelColor
            }
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
}
