import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var attentionDot: NSView?
    private var attentionMenuItems: [NSMenuItem] = []
    private var attentionSeparator: NSMenuItem?
    private var lastAttentionCount: Int = 0
    private var switcherPanel: SwitcherPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var backtickHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var navHotKeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 6)
    private var mouseMonitor: Any?
    private var pollTimer: Timer?
    private var dockAutohideItem: NSMenuItem?
    private var addAppPanel: AddAppPanel?
    private var dockManagePanel: DockManagePanel?

    // Hold-Tab auto-cycle: tap still fires once via the Carbon hotkey; if Tab
    // stays down past initialDelay, the poll timer cycles every `interval`.
    private var tabHeldSince: Date?
    private var nextTabRepeatAt: Date?
    private let tabRepeatInitialDelay: TimeInterval = 0.35
    private let tabRepeatInterval: TimeInterval = 0.22

    private var lastSuppressBouncing: Bool = Prefs.shared.suppressBouncing

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        installHotKeyHandler()
        registerHotKey()
        applyBounceSuppressionIfNeeded()
        AttentionTracker.shared.start()
        // Re-register the global hotkey whenever the user changes settings,
        // and apply the bounce-suppression toggle when it changes.
        NotificationCenter.default.addObserver(
            forName: Prefs.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.unregisterMainHotKey()
            self?.registerHotKey()
            self?.applyBounceSuppressionIfChanged()
        }
        NotificationCenter.default.addObserver(
            forName: AttentionTracker.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAttentionUI()
        }
    }

    // MARK: - Attention indicators

    private func installAttentionDot(in button: NSStatusBarButton) {
        let size: CGFloat = 9
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = size / 2
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.borderColor = NSColor.white.cgColor
        dot.layer?.borderWidth = 1.0
        // Pinned to upper-right so it stays put if the button resizes
        // (the dot itself never changes size).
        let x = button.bounds.width - size - 1
        let y = button.bounds.height - size - 1
        dot.frame = NSRect(x: x, y: y, width: size, height: size)
        dot.autoresizingMask = [.minXMargin, .minYMargin]
        dot.isHidden = true
        button.addSubview(dot)
        attentionDot = dot
    }

    private func refreshAttentionUI() {
        let count = AttentionTracker.shared.attentionPIDs.count
        let wasZero = (lastAttentionCount == 0)
        lastAttentionCount = count
        attentionDot?.isHidden = (count == 0)
        // Brief one-shot pulse on the 0 -> N transition to catch the eye.
        if count > 0 && wasZero { pulseAttentionDot() }
    }

    private func pulseAttentionDot() {
        guard let layer = attentionDot?.layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values   = [0.7, 1.2, 1.0]
        anim.keyTimes = [0, 0.5, 1.0]
        anim.duration = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "attentionAppearancePulse")
    }

    private func rebuildAttentionMenuSection(in menu: NSMenu) {
        // Wipe any prior attention rows + their separator.
        for item in attentionMenuItems { menu.removeItem(item) }
        attentionMenuItems.removeAll()
        if let sep = attentionSeparator { menu.removeItem(sep); attentionSeparator = nil }

        let apps = AttentionTracker.shared.attentionApps
        guard !apps.isEmpty else { return }

        var inserted: [NSMenuItem] = []
        for (i, info) in apps.enumerated() {
            let item = NSMenuItem(
                title: "\(info.appName) — needs attention",
                action: #selector(activateAttentionApp(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: Int(info.pid))
            if let icon = info.appIcon {
                let copy = icon.copy() as? NSImage ?? icon
                copy.size = NSSize(width: 16, height: 16)
                item.image = copy
            }
            menu.insertItem(item, at: i)
            inserted.append(item)
        }
        let sep = NSMenuItem.separator()
        menu.insertItem(sep, at: inserted.count)
        attentionSeparator = sep
        attentionMenuItems = inserted
    }

    @objc private func activateAttentionApp(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        let pid = pid_t(n.intValue)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        // activateAllWindows is what brings a hidden modal sheet to the front
        // (and switches Space if the app's main window is on a different one).
        // Plain activate() leaves the dialog behind whatever's covering it.
        app.activate(options: [.activateAllWindows])
    }

    // MARK: - Dock bounce suppression

    private func applyBounceSuppression() {
        let suppress = Prefs.shared.suppressBouncing
        let cmd = suppress
            ? "defaults write com.apple.dock no-bouncing -bool true && killall Dock"
            : "defaults delete com.apple.dock no-bouncing 2>/dev/null; killall Dock"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }

    // Same as `applyBounceSuppression`, but skips the `killall Dock` (and the
    // accompanying Dock relaunch flash) when the live Dock pref already matches
    // our desired state. Used at launch so opening DockGone doesn't always
    // restart the Dock.
    private func applyBounceSuppressionIfNeeded() {
        let desired = Prefs.shared.suppressBouncing
        let current = currentNoBouncing()
        guard current != desired else { return }
        applyBounceSuppression()
    }

    private func currentNoBouncing() -> Bool {
        let pipe = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "com.apple.dock", "no-bouncing"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out == "1"
    }

    private func applyBounceSuppressionIfChanged() {
        let current = Prefs.shared.suppressBouncing
        guard current != lastSuppressBouncing else { return }
        lastSuppressBouncing = current
        applyBounceSuppression()
    }

    // Double-clicking DockGone.app while a copy is already running (the
    // launchd KeepAlive case) fires this. Open the Preferences window so
    // the .app icon doubles as a Preferences launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    private func unregisterMainHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = backtickHotKeyRef { UnregisterEventHotKey(ref); backtickHotKeyRef = nil }
    }

    // MARK: - Hotkeys

    // Install the Carbon event handler exactly once at launch. Previously this
    // ran inside registerHotKey(), which re-fires on every Prefs change —
    // leaving stale EventHandlerRefs and a stack of handlers that each
    // dispatched the hotkey callback.
    private func installHotKeyHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, inEvent, userData) -> OSStatus in
                guard let ptr = userData, let inEvent = inEvent else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(inEvent,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkID)
                let me = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                let id = hkID.id
                DispatchQueue.main.async {
                    switch id {
                    case 1: me.handleHotKey()
                    case 2: me.switcherPanel?.moveLeft()
                    case 3: me.switcherPanel?.moveRight()
                    case 4: me.switcherPanel?.moveUp()
                    case 5: me.switcherPanel?.moveDown()
                    case 6: me.removeMonitors(); me.switcherPanel?.dismiss()
                    case 7: me.switcherPanel?.cyclePrev()
                    case 8: me.handleBacktickHotKey()
                    default: break
                    }
                }
                return noErr
            },
            1, &eventType, ptr, &eventHandlerRef
        )
    }

    private func registerHotKey() {
        let sig: OSType = 0x444B4C43
        let mods = Prefs.shared.hotkeyModifiers
        let mainID = EventHotKeyID(signature: sig, id: 1)
        RegisterEventHotKey(Prefs.shared.hotkeyKeyCode, mods, mainID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        // Modifier + ` is the backwards-cycle companion to modifier + Tab,
        // matching macOS Cmd+`/Cmd+Shift+Tab semantics.
        let backtickID = EventHotKeyID(signature: sig, id: 8)
        RegisterEventHotKey(UInt32(kVK_ANSI_Grave), mods, backtickID,
                            GetApplicationEventTarget(), 0, &backtickHotKeyRef)
    }

    // Registered when the panel is visible, removed on dismiss.
    // Carbon hotkeys fire system-wide regardless of which app is key —
    // unlike local NSEvent monitors which fail when our accessory app isn't active.
    private func registerNavHotKeys() {
        let sig: OSType = 0x444B4C43
        // Nav keys piggyback on the user-chosen modifier (which is held while
        // the panel is visible). Shift-Tab additionally requires shift.
        let mod = Prefs.shared.hotkeyModifiers
        let keys: [(Int, UInt32, UInt32)] = [
            (kVK_LeftArrow,  mod,                    2),
            (kVK_RightArrow, mod,                    3),
            (kVK_UpArrow,    mod,                    4),
            (kVK_DownArrow,  mod,                    5),
            (kVK_Escape,     mod,                    6),
            (kVK_Tab,        mod | UInt32(shiftKey), 7),
        ]
        for (i, (vk, mod, hkid)) in keys.enumerated() {
            let hkID = EventHotKeyID(signature: sig, id: hkid)
            RegisterEventHotKey(UInt32(vk), mod, hkID,
                                GetApplicationEventTarget(), 0, &navHotKeyRefs[i])
        }
    }

    // The single NSEvent.ModifierFlag corresponding to the primary Carbon
    // modifier the user picked. Used to detect "modifier released" so the
    // panel can commit its selection.
    private var primaryModifierFlag: NSEvent.ModifierFlags {
        let m = Prefs.shared.hotkeyModifiers
        if m & UInt32(controlKey) != 0 { return .control }
        if m & UInt32(optionKey)  != 0 { return .option }
        if m & UInt32(shiftKey)   != 0 { return .shift }
        if m & UInt32(cmdKey)     != 0 { return .command }
        return .option
    }

    private func unregisterNavHotKeys() {
        for i in 0..<navHotKeyRefs.count {
            if let ref = navHotKeyRefs[i] { UnregisterEventHotKey(ref) }
            navHotKeyRefs[i] = nil
        }
    }

    func handleHotKey() {
        if let panel = switcherPanel, panel.isVisible {
            panel.cycleNext()
        } else {
            showSwitcher()
        }
    }

    func handleBacktickHotKey() {
        if let panel = switcherPanel, panel.isVisible {
            panel.cyclePrev()
        } else {
            showSwitcher()
            switcherPanel?.cyclePrev()
        }
    }

    // MARK: - Switcher

    // Forcibly hide and close any of our aux windows (Add to Dock, Edit Dock).
    // Called before opening any new window so they can't stack or leak.
    private func dismissAuxPanels() {
        for window in NSApp.windows {
            if window is AddAppPanel || window is DockManagePanel {
                window.alphaValue = 0
                window.orderOut(nil)
                window.close()
            }
        }
        addAppPanel = nil
        dockManagePanel = nil
    }

    private func showSwitcher() {
        dismissAuxPanels()
        let size = Prefs.shared.iconSize
        let attentionList = AttentionTracker.shared.attentionApps
        var apps = DockReader.getUnopenedApps(attentionApps: attentionList)
        // Attention-pending apps go first so the user can reach them with
        // a single tap of the hotkey.
        apps.sort { ($0.attentionPID != nil) && ($1.attentionPID == nil) }
        if Prefs.shared.includeTrash {
            apps.append(DockReader.getTrashEntry())
        }
        // Single "Close" tile at the end — selecting it dismisses without
        // launching anything.
        apps.append(DockReader.getCloseEntry(size: size))
        guard !apps.isEmpty else { return }

        let panel = SwitcherPanel(apps: apps)
        panel.onDismiss = { [weak self] in
            self?.removeMonitors()
            self?.switcherPanel = nil
        }
        panel.show()
        switcherPanel = panel
        registerNavHotKeys()

        let modFlag = primaryModifierFlag
        if !NSEvent.modifierFlags.contains(modFlag) {
            panel.launch()
            return
        }

        // Poll the modifier at 10 Hz: detect release (commit selection)
        // AND advance hold-Tab cycling past the initial-delay warm-up.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !NSEvent.modifierFlags.contains(modFlag) {
                self.stopPolling()
                self.switcherPanel?.launchHovered()
                return
            }
            self.pollTabRepeat()
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard NSEvent.modifierFlags.contains(modFlag) else { return }
            DispatchQueue.main.async {
                self?.removeMonitors()
                self?.switcherPanel?.dismiss()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        tabHeldSince = nil
        nextTabRepeatAt = nil
    }

    private func pollTabRepeat() {
        let tabKey = CGKeyCode(Prefs.shared.hotkeyKeyCode)
        let graveKey = CGKeyCode(kVK_ANSI_Grave)
        let tabDown = CGEventSource.keyState(.combinedSessionState, key: tabKey)
        let graveDown = CGEventSource.keyState(.combinedSessionState, key: graveKey)
        guard tabDown || graveDown else {
            tabHeldSince = nil
            nextTabRepeatAt = nil
            return
        }
        let now = Date()
        if tabHeldSince == nil {
            tabHeldSince = now
            nextTabRepeatAt = now.addingTimeInterval(tabRepeatInitialDelay)
            return
        }
        if let next = nextTabRepeatAt, now >= next {
            if graveDown || NSEvent.modifierFlags.contains(.shift) {
                switcherPanel?.cyclePrev()
            } else {
                switcherPanel?.cycleNext()
            }
            nextTabRepeatAt = now.addingTimeInterval(tabRepeatInterval)
        }
    }

    private func removeMonitors() {
        stopPolling()
        unregisterNavHotKeys()
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            btn.image = NSImage(systemSymbolName: "dock.rectangle",
                                accessibilityDescription: "Dock Launcher")
            installAttentionDot(in: btn)
        }
        let menu = NSMenu()
        menu.delegate = self

        let autohideItem = NSMenuItem(title: "Hide Dock",
                                      action: #selector(toggleDockHidden(_:)),
                                      keyEquivalent: "")
        autohideItem.target = self
        autohideItem.state = isDockHidden() ? .on : .off
        menu.addItem(autohideItem)
        dockAutohideItem = autohideItem

        let addAppItem = NSMenuItem(title: "Add to Dock",
                                    action: #selector(showAddAppWindow),
                                    keyEquivalent: "")
        addAppItem.target = self
        menu.addItem(addAppItem)

        let manageItem = NSMenuItem(title: "Edit Dock",
                                    action: #selector(showManageDockWindow),
                                    keyEquivalent: "")
        manageItem.target = self
        menu.addItem(manageItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences",
                                   action: #selector(showPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginEnabled ? .on : .off
        menu.addItem(loginItem)

        let diagItem = NSMenuItem(title: "Diagnose Attention…",
                                  action: #selector(runDiagnoseAttention),
                                  keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DockGone",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func runDiagnoseAttention() {
        DiagnoseAttention.writeReport()
    }

    // MARK: - Dock Hide

    // "Disabled" means autohide=true + a huge delay so it never slides in on hover.
    private func isDockHidden() -> Bool {
        let pipe = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "com.apple.dock", "autohide-delay"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (Double(out ?? "") ?? 0) >= 9999
    }

    @objc private func toggleDockHidden(_ sender: NSMenuItem) {
        let hide = sender.state != .on
        let cmd: String
        if hide {
            cmd = "defaults write com.apple.dock autohide -bool true && defaults write com.apple.dock autohide-delay -float 9999 && killall Dock"
        } else {
            cmd = "defaults delete com.apple.dock autohide-delay && defaults write com.apple.dock autohide -bool false && killall Dock"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
        sender.state = hide ? .on : .off
    }

    // MARK: - Add App to Dock

    @objc private func showAddAppWindow() {
        dismissAuxPanels()
        let apps = DockReader.getAllAppsNotInDock()
        let panel = AddAppPanel(apps: apps)
        panel.onConfirm = { selected in
            DockReader.addAppsToDock(selected)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addAppPanel = panel
    }

    @objc private func showManageDockWindow() {
        dismissAuxPanels()
        let apps = DockReader.getDockApps()
        guard !apps.isEmpty else { return }
        let panel = DockManagePanel(apps: apps)
        panel.onDismiss = { [weak self] in self?.dockManagePanel = nil }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dockManagePanel = panel
    }

    // MARK: - Launch at Login

    private var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.user.dockgone.plist")
    }

    private var loginEnabled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    @objc private func showPreferences() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        if loginEnabled { removeLoginItem(); sender.state = .off }
        else            { addLoginItem();    sender.state = .on  }
    }

    private func addLoginItem() {
        let binary = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let plist: [String: Any] = [
            "Label": "com.user.dockgone",
            "ProgramArguments": [binary],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? FileManager.default.createDirectory(
                at: agentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: agentPlistURL)
        }
        launchctl("load", agentPlistURL.path)
    }

    private func removeLoginItem() {
        launchctl("unload", agentPlistURL.path)
        try? FileManager.default.removeItem(at: agentPlistURL)
    }

    private func launchctl(_ cmd: String, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = [cmd, path]
        try? p.run()
        p.waitUntilExit()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        dockAutohideItem?.state = isDockHidden() ? .on : .off
        rebuildAttentionMenuSection(in: menu)
    }
}
