import AppKit
import ServiceManagement
import UsageCore

/// The whole UI: a status item title, and a menu built only while it is open.
///
/// Idle cost is one coalesced timer wake per interval. Nothing repaints on its
/// own, no view hierarchy exists, and the menu is rebuilt on demand rather than
/// kept in sync.
@MainActor
final class StatusController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Past this the figure turns red: the plan is about to stop the next turn.
    private static let criticalPercent: Double = 90

    /// Opening the menu is cheap to ask for and expensive to serve, so it only
    /// triggers a probe when the cached figures are older than this.
    private static let staleAfter: TimeInterval = 60

    /// Timer wakes are coalesced with everything else the system has to do.
    private static let timerLeeway: DispatchTimeInterval = .seconds(30)

    /// Brand marks sit next to a 12 pt figure, so they render at 13 pt.
    private static let iconSize: CGFloat = 13

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let rowFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    private var iconCache: [ProviderKind: NSImage] = [:]

    private var usage: [ProviderKind: ProviderUsage] = [:]
    private var lastRefresh: Date?
    private var refreshTask: Task<Void, Never>?
    private var timer: DispatchSourceTimer?
    private var menuIsOpen = false
    private var loginItemError: String?
    private var renderedTitle: String?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        // Rows carry no action, and auto-enabling would grey every one of them.
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.title = "AI …"
        observePowerEvents()
        startTimer()
        refresh(force: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopTimer() }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startTimer()
                self?.refresh(force: true)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        let interval = Preferences.refreshInterval
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: Self.timerLeeway
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
        source.activate()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Probing

    private func refresh(force: Bool) {
        guard refreshTask == nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.staleAfter {
            return
        }
        refreshTask = Task { [weak self] in
            async let claude = ClaudeProbe.run()
            async let codex = CodexProbe.run()
            let results = await (claude, codex)
            guard let self else { return }
            self.apply(results.0, results.1)
        }
    }

    private func apply(_ claude: ProviderUsage, _ codex: ProviderUsage) {
        refreshTask = nil
        usage[.claude] = claude
        usage[.codex] = codex
        lastRefresh = Date()
        render()
        // Landing figures while the menu is open should update it in place.
        if menuIsOpen { menu.update() }
    }

    // MARK: - Status bar title

    private func render() {
        guard let button = statusItem.button else { return }

        var plain = ""
        let title = NSMutableAttributedString()
        for kind in ProviderKind.allCases {
            guard let segment = segment(for: kind) else { continue }
            if !plain.isEmpty {
                plain += " · "
                title.append(
                    NSAttributedString(
                        string: " · ",
                        attributes: [.font: rowFont, .foregroundColor: NSColor.tertiaryLabelColor]
                    ))
            }
            appendIcon(for: kind, to: title, plain: &plain)
            plain += segment.text
            title.append(
                NSAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: rowFont,
                        .foregroundColor: segment.critical ? NSColor.systemRed : NSColor.labelColor,
                    ]
                ))
        }

        if plain.isEmpty {
            plain = lastRefresh == nil ? "AI …" : "AI –"
            title.append(
                NSAttributedString(
                    string: plain,
                    attributes: [.font: rowFont, .foregroundColor: NSColor.secondaryLabelColor]
                ))
        }

        // A menu bar item that re-sets an identical title still re-lays out.
        guard plain != renderedTitle else { return }
        renderedTitle = plain
        button.attributedTitle = title
    }

    /// The provider's brand mark, then a space. Falls back to the text badge
    /// when the icon is missing, so an unbundled run still reads as a provider.
    private func appendIcon(
        for kind: ProviderKind, to title: NSMutableAttributedString, plain: inout String
    ) {
        guard let image = icon(for: kind) else {
            plain += kind.badge
            title.append(
                NSAttributedString(
                    string: kind.badge,
                    attributes: [.font: rowFont, .foregroundColor: NSColor.labelColor]
                ))
            return
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Vertical center against the cap height, not the ascender, so a 13 pt
        // icon sits on the same optical line as a 12 pt figure.
        let size = Self.iconSize
        attachment.bounds = NSRect(
            x: 0,
            y: (rowFont.capHeight - size) / 2,
            width: size,
            height: size
        )
        title.append(NSAttributedString(attachment: attachment))
        title.append(NSAttributedString(string: " ", attributes: [.font: rowFont]))
        plain += "·"
    }

    /// The provider's brand mark in its own colors — Claude's terracotta, the
    /// OpenAI knot in ChatGPT green — so the two read at a glance and on both
    /// light and dark menu bars. Loaded once.
    private func icon(for kind: ProviderKind) -> NSImage? {
        if let cached = iconCache[kind] { return cached }
        guard
            let url = Bundle.main.url(forResource: kind.iconResourceName, withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        iconCache[kind] = image
        return image
    }

    /// One provider's slice of the title, or nil when it has nothing to gauge —
    /// an unsigned-in CLI should take no room in the menu bar.
    private func segment(for kind: ProviderKind) -> (text: String, critical: Bool)? {
        guard let provider = usage[kind] else { return nil }
        switch provider.status {
        case .ok:
            guard let percent = provider.bindingPercent else { return nil }
            return (Format.percent(percent), percent >= Self.criticalPercent)
        case .unauthenticated, .unsupported:
            return nil
        case .unavailable:
            return ("!", false)
        }
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refresh(force: false)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let now = Date()
        menu.removeAllItems()

        if usage.isEmpty {
            menu.addItem(infoItem("Reading plan quotas…"))
        }
        for kind in ProviderKind.allCases {
            guard let provider = usage[kind] else { continue }
            menu.addItem(.sectionHeader(title: header(for: provider)))
            appendRows(for: provider, to: menu, now: now)
        }

        menu.addItem(.separator())
        menu.addItem(infoItem(lastRefresh.map { Format.age($0, now: now) } ?? "not read yet"))
        if let loginItemError {
            menu.addItem(infoItem(loginItemError))
        }
        menu.addItem(actionItem("Refresh Now", #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(intervalItem())
        menu.addItem(launchAtLoginItem())
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit AI Usage Monitor", #selector(quit), keyEquivalent: "q"))
    }

    private func header(for provider: ProviderUsage) -> String {
        guard let plan = provider.planLabel else { return provider.provider.displayName }
        return "\(provider.provider.displayName) — \(plan)"
    }

    private func appendRows(for provider: ProviderUsage, to menu: NSMenu, now: Date) {
        guard provider.status == .ok else {
            menu.addItem(infoItem(provider.detail ?? "No plan quota reported."))
            return
        }
        guard !provider.windows.isEmpty else {
            menu.addItem(infoItem("This plan reports no rolling windows."))
            return
        }
        for window in provider.windows {
            menu.addItem(windowItem(window, now: now))
        }
        if !provider.extraWindows.isEmpty {
            menu.addItem(infoItem("Other allowances"))
            for window in provider.extraWindows {
                menu.addItem(windowItem(window, now: now))
            }
        }
    }

    /// `████░░░░░░   44%  5 hour · resets in 2h 10m`. Bar and percentage are
    /// fixed-width in a monospaced font, so the rows line up without tab stops.
    private func windowItem(_ window: UsageWindow, now: Date) -> NSMenuItem {
        let percent = Format.percent(window.usedPercent)
        let padding = String(repeating: " ", count: max(0, 4 - percent.count))
        var text = "\(Format.bar(window.usedPercent)) \(padding)\(percent)  \(window.label)"
        if let resetsAt = window.resetsAt {
            text += " · \(Format.reset(resetsAt, now: now))"
        }

        let critical = window.usedPercent >= Self.criticalPercent
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: rowFont,
                .foregroundColor: critical ? NSColor.systemRed : NSColor.labelColor,
            ]
        )
        return item
    }

    private func infoItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func actionItem(
        _ title: String,
        _ selector: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func intervalItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Refresh Every", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = Preferences.refreshInterval
        for option in Preferences.intervalOptions {
            let minutes = Int(option / 60)
            let child = NSMenuItem(
                title: "\(minutes) minutes",
                action: #selector(setInterval(_:)),
                keyEquivalent: ""
            )
            child.target = self
            child.representedObject = option
            child.state = option == current ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    private func launchAtLoginItem() -> NSMenuItem {
        let item = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        refresh(force: true)
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Preferences.refreshInterval = interval
        startTimer()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            loginItemError = nil
        } catch {
            // Registration needs a signed bundle; an unbundled `swift run` cannot.
            loginItemError = "Login item failed: \(error.localizedDescription)"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
