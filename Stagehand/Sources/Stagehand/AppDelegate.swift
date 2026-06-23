import AppKit

/// Owns the menu bar item and routes every user action. The menu is rebuilt on
/// each open (`menuNeedsUpdate`) so the profile list, login-item state and last
/// restore warnings are always current.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    /// Warnings from the most recent restore, surfaced as disabled rows so the
    /// user learns which apps were skipped without an interrupting dialog.
    private var lastRestoreWarnings: [String] = []
    /// True while a restore is running, to disable re-entry and show progress.
    private var isRestoring = false

    /// Debounces the display-change trigger — displays fire several notifications
    /// as they settle, and we only want to restore once.
    private var displayChangeWork: DispatchWorkItem?

    private let firstLaunchKey = "Stagehand.didShowAccessibilityExplainer"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        ProfileManagerWindowController.shared.onRestore = { [weak self] profile in
            self?.beginRestore(profile)
        }
        requestAccessibilityIfFirstLaunch()
        applyArrangeShortcuts()
        observeDisplayChanges()
        scheduleLaunchRestore()
    }

    // MARK: Automation (Moom-style triggers + global snap shortcuts)

    /// Register or tear down the global window-snap hotkeys to match the setting.
    private func applyArrangeShortcuts() {
        if Settings.arrangeShortcutsEnabled {
            HotKeyManager.shared.registerArrangeShortcuts { WindowArranger.apply($0) }
        } else {
            HotKeyManager.shared.unregisterAll()
        }
    }

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// When the display arrangement changes (a monitor connected/disconnected, a
    /// resolution change), re-apply the chosen profile once things settle.
    @objc private func displaysChanged() {
        guard let id = Settings.displayChangeProfileID,
              let profile = ProfileStore.shared.profile(id: id) else { return }
        displayChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard AccessibilityManager.isTrusted else { return }
            self?.beginRestore(profile)
        }
        displayChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Shortly after launch (e.g. at login), restore the designated profile so a
    /// fresh session comes up arranged. Skipped silently until Accessibility is
    /// granted.
    private func scheduleLaunchRestore() {
        guard let id = Settings.launchRestoreProfileID,
              let profile = ProfileStore.shared.profile(id: id) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard AccessibilityManager.isTrusted else { return }
            self?.beginRestore(profile)
        }
    }

    /// On first launch only, explain the Accessibility requirement before the
    /// system's own prompt appears. After that we stay quiet unless the user
    /// tries an action that needs it.
    private func requestAccessibilityIfFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstLaunchKey) else { return }
        defaults.set(true, forKey: firstLaunchKey)
        if !AccessibilityManager.isTrusted {
            AccessibilityManager.presentFirstLaunchExplainer()
        }
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Stagehand window layouts")

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // — Saved profiles —
        let profiles = ProfileStore.shared.profiles
        if profiles.isEmpty {
            let empty = NSMenuItem(title: "No saved profiles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Restore Layout", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for profile in profiles {
                let item = NSMenuItem(
                    title: "  \(profile.name)",
                    action: #selector(restoreProfile(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.toolTip = "\(profile.apps.count) apps · \(profile.windowCount) windows"
                item.isEnabled = !isRestoring
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // — Capture —
        let save = NSMenuItem(title: isRestoring ? "Restoring…" : "Save current layout…",
                              action: #selector(saveCurrentLayout),
                              keyEquivalent: "s")
        save.target = self
        save.isEnabled = !isRestoring
        menu.addItem(save)

        let manage = NSMenuItem(title: "Manage Profiles…",
                                action: #selector(showProfileManager),
                                keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        // — Window arranging (Moom/Magnet/Rectangle-style) + automation —
        menu.addItem(.separator())
        menu.addItem(makeArrangeSubmenuItem())
        menu.addItem(makeAutomationSubmenuItem())

        // — Last-restore warnings —
        if !lastRestoreWarnings.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Last restore", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for warning in lastRestoreWarnings {
                let item = NSMenuItem(title: "  ⚠︎ \(warning)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // — Accessibility status —
        let trusted = AccessibilityManager.isTrusted
        let axItem = NSMenuItem(
            title: trusted ? "Accessibility: Granted" : "Enable Accessibility…",
            action: trusted ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: "")
        axItem.target = self
        axItem.isEnabled = !trusted
        if !trusted { axItem.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                             accessibilityDescription: nil) }
        menu.addItem(axItem)

        // — Login item —
        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Stagehand",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Submenu builders

    private func makeArrangeSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Arrange Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Visually grouped like the popular snappers: halves, quarters, thirds,
        // and the catch-all maximize/center/next-display. Rows stay enabled even
        // without Accessibility so a click surfaces the permission prompt.
        let groups: [[WindowArranger.Action]] = [
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
            [.maximize, .center, .nextDisplay],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for action in group {
                let label = Shortcut.binding(for: action)?.label
                let title = label.map { "\(action.title)   \($0)" } ?? action.title
                let row = NSMenuItem(title: title, action: #selector(arrangeWindow(_:)),
                                     keyEquivalent: "")
                row.target = self
                row.representedObject = action.rawValue
                submenu.addItem(row)
            }
        }
        item.submenu = submenu
        return item
    }

    private func makeAutomationSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Automation", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let shortcuts = NSMenuItem(title: "Window Snap Shortcuts",
                                   action: #selector(toggleArrangeShortcuts), keyEquivalent: "")
        shortcuts.target = self
        shortcuts.state = Settings.arrangeShortcutsEnabled ? .on : .off
        shortcuts.toolTip = "Global Control-Option shortcuts to snap the focused window."
        submenu.addItem(shortcuts)

        submenu.addItem(.separator())
        let displayHeader = NSMenuItem(title: "Restore on Display Change", action: nil, keyEquivalent: "")
        displayHeader.isEnabled = false
        submenu.addItem(displayHeader)
        addProfilePicker(to: submenu, selected: Settings.displayChangeProfileID,
                         action: #selector(setDisplayTriggerProfile(_:)))

        submenu.addItem(.separator())
        let launchHeader = NSMenuItem(title: "Restore at Launch", action: nil, keyEquivalent: "")
        launchHeader.isEnabled = false
        submenu.addItem(launchHeader)
        addProfilePicker(to: submenu, selected: Settings.launchRestoreProfileID,
                         action: #selector(setLaunchTriggerProfile(_:)))

        item.submenu = submenu
        return item
    }

    /// Adds an "Off" row plus one checkable row per profile; the checked row is
    /// the currently selected trigger profile.
    private func addProfilePicker(to menu: NSMenu, selected: UUID?, action: Selector) {
        let off = NSMenuItem(title: "  Off", action: action, keyEquivalent: "")
        off.target = self
        off.representedObject = ""
        off.state = (selected == nil) ? .on : .off
        menu.addItem(off)

        for profile in ProfileStore.shared.profiles {
            let row = NSMenuItem(title: "  \(profile.name)", action: action, keyEquivalent: "")
            row.target = self
            row.representedObject = profile.id.uuidString
            row.state = (selected == profile.id) ? .on : .off
            menu.addItem(row)
        }
    }

    // MARK: Actions

    @objc private func saveCurrentLayout() {
        guard ensureTrusted(for: "save the current layout") else { return }

        let apps = LayoutEngine.captureCurrentLayout()
        guard !apps.isEmpty else {
            presentInfo("Nothing to save",
                        "No app windows were found to capture.")
            return
        }

        guard let name = promptForText(
            title: "Save Layout",
            message: "Name this layout profile (e.g. Work, Study, Deep Focus). "
                + "Saving over an existing name updates it.",
            defaultValue: suggestedProfileName())
        else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ProfileStore.shared.saveProfile(named: trimmed, apps: apps)
        presentInfo("Layout saved",
                    "“\(trimmed)” captured \(apps.count) apps and \(apps.windowCount) windows.")
    }

    @objc private func restoreProfile(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let profile = ProfileStore.shared.profile(id: id) else { return }
        beginRestore(profile)
    }

    private func beginRestore(_ profile: LayoutProfile) {
        guard !isRestoring else { return }
        guard ensureTrusted(for: "restore a layout") else { return }

        isRestoring = true
        lastRestoreWarnings = []
        Task { @MainActor in
            let outcomes = await LayoutEngine.restore(profile)
            self.lastRestoreWarnings = outcomes.compactMap { $0.warning }
            self.isRestoring = false
        }
    }

    @objc private func showProfileManager() {
        ProfileManagerWindowController.shared.show()
    }

    @objc private func arrangeWindow(_ sender: NSMenuItem) {
        guard ensureTrusted(for: "arrange the window") else { return }
        guard let raw = sender.representedObject as? String,
              let action = WindowArranger.Action(rawValue: raw) else { return }
        WindowArranger.apply(action)
    }

    @objc private func toggleArrangeShortcuts() {
        Settings.arrangeShortcutsEnabled.toggle()
        applyArrangeShortcuts()
    }

    @objc private func setDisplayTriggerProfile(_ sender: NSMenuItem) {
        Settings.displayChangeProfileID = profileID(from: sender)
    }

    @objc private func setLaunchTriggerProfile(_ sender: NSMenuItem) {
        Settings.launchRestoreProfileID = profileID(from: sender)
    }

    /// A menu item's represented profile id, or nil for the "Off" row.
    private func profileID(from sender: NSMenuItem) -> UUID? {
        guard let raw = sender.representedObject as? String, !raw.isEmpty else { return nil }
        return UUID(uuidString: raw)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityManager.triggerSystemPrompt()
        AccessibilityManager.openSystemSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            if LoginItem.requiresApproval {
                presentInfo("Approval needed",
                            "Enable Stagehand under System Settings ▸ General ▸ Login Items.")
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                presentInfo("Couldn't change login item", error.localizedDescription)
            }
        }
    }

    // MARK: Helpers

    /// Confirms Accessibility is granted before an action; otherwise prompts and
    /// returns false so the caller can bail out.
    private func ensureTrusted(for action: String) -> Bool {
        guard AccessibilityManager.isTrusted else {
            AccessibilityManager.presentBlockedActionAlert(action: action)
            return false
        }
        return true
    }

    /// A friendly default name that won't collide with existing profiles, so the
    /// prefilled value never silently overwrites one if accepted as-is.
    private func suggestedProfileName() -> String {
        let existing = Set(ProfileStore.shared.profiles.map { $0.name.lowercased() })
        if let preset = ["Work", "Study", "Deep Focus"].first(where: {
            !existing.contains($0.lowercased())
        }) {
            return preset
        }
        var n = 1
        while existing.contains("layout \(n)") { n += 1 }
        return "Layout \(n)"
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func presentInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Menu refresh

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
