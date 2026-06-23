import AppKit
import ApplicationServices

/// The heart of Stagehand: turn the current desktop into a `LayoutProfile`
/// (capture) and turn a `LayoutProfile` back into the desktop (restore).
///
/// Nothing here touches persistence or UI — it deals only in the Codable model
/// and the Accessibility API.
enum LayoutEngine {

    // MARK: Capture

    /// Snapshot every regular app's standard windows.
    ///
    /// Only `.regular` apps (the ones that show in the Dock) are considered, and
    /// Stagehand excludes itself. Apps with no standard windows are dropped so
    /// profiles stay meaningful.
    static func captureCurrentLayout() -> [SavedApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var captured: [SavedApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier
            else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windowElements = AX.windows(of: appElement)

            var savedWindows: [SavedWindow] = []
            for window in windowElements {
                // Keep ordinary document windows; skip palettes/sheets/etc.
                guard AX.isStandardWindow(window), let frame = AX.frame(of: window) else { continue }

                var displayID: UInt32?
                var spaceID: UInt64?
                if let windowID = AX.windowID(of: window) {
                    displayID = DisplayInfo.displayID(containing:
                        CGPoint(x: frame.midX, y: frame.midY))
                    spaceID = SpaceInfo.spaceID(for: windowID)
                }

                savedWindows.append(SavedWindow(
                    title: AX.string(window, kAXTitleAttribute as String) ?? "",
                    frame: WindowFrame(frame),
                    minimized: AX.bool(window, kAXMinimizedAttribute as String) ?? false,
                    displayID: displayID,
                    spaceID: spaceID
                ))
            }

            guard !savedWindows.isEmpty else { continue }

            captured.append(SavedApp(
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                bundlePath: app.bundleURL?.path,
                windows: savedWindows
            ))
        }
        return captured
    }

    // MARK: Restore

    /// Result of restoring one app, used to build the warning summary.
    struct RestoreOutcome {
        var appName: String
        var positioned: Int
        var warning: String?
    }

    /// Reopen and reposition everything in `profile`.
    ///
    /// For each app: launch it if it isn't running, wait (briefly) for its
    /// windows to exist, then match saved windows to live windows and apply the
    /// saved frame. Failures are non-fatal — they become warnings the caller can
    /// surface in the menu.
    static func restore(_ profile: LayoutProfile) async -> [RestoreOutcome] {
        var outcomes: [RestoreOutcome] = []
        for savedApp in profile.apps {
            outcomes.append(await restore(app: savedApp))
        }
        return outcomes
    }

    private static func restore(app savedApp: SavedApp) async -> RestoreOutcome {
        // 1. Make sure the app is running, launching it if necessary.
        let runningApp: NSRunningApplication
        if let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: savedApp.bundleID).first {
            runningApp = existing
        } else {
            guard let url = resolveAppURL(for: savedApp) else {
                return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                      warning: "\(savedApp.name) isn't installed — skipped")
            }
            do {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                runningApp = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            } catch {
                return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                      warning: "\(savedApp.name) failed to launch — skipped")
            }
        }

        // 2. Wait for the app to publish its windows (newly launched apps take a
        //    beat). Poll up to ~5s, then give up gracefully.
        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var liveWindows = AX.windows(of: appElement)
        var attempts = 0
        while liveWindows.isEmpty && attempts < 20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            liveWindows = AX.windows(of: appElement)
            attempts += 1
        }
        guard !liveWindows.isEmpty else {
            return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                  warning: "\(savedApp.name) opened but exposed no windows")
        }

        // 3. Apply each saved frame to a matched live window.
        var available = liveWindows
        var positioned = 0
        for savedWindow in savedApp.windows {
            guard let index = matchIndex(for: savedWindow, in: available) else { continue }
            let target = available.remove(at: index)

            // Un-minimize before moving (you can't reposition a minimized window),
            // then re-apply the saved minimized state afterwards.
            if AX.bool(target, kAXMinimizedAttribute as String) == true {
                AX.setMinimized(target, false)
            }
            AX.setFrame(target, savedWindow.frame.cgRect)
            if savedWindow.minimized {
                AX.setMinimized(target, true)
            }
            positioned += 1
        }

        let warning = positioned < savedApp.windows.count
            ? "\(savedApp.name): positioned \(positioned)/\(savedApp.windows.count) windows"
            : nil
        return RestoreOutcome(appName: savedApp.name, positioned: positioned, warning: warning)
    }

    /// Prefer an exact title match (handles reordered windows); fall back to the
    /// first still-available window so single-window apps always get placed.
    private static func matchIndex(for savedWindow: SavedWindow,
                                   in windows: [AXUIElement]) -> Int? {
        if !savedWindow.title.isEmpty,
           let exact = windows.firstIndex(where: {
               AX.string($0, kAXTitleAttribute as String) == savedWindow.title
           }) {
            return exact
        }
        return windows.isEmpty ? nil : 0
    }

    /// Locate the app on disk: by bundle id first (survives the app moving), then
    /// the captured path as a fallback.
    private static func resolveAppURL(for savedApp: SavedApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: savedApp.bundleID) {
            return url
        }
        if let path = savedApp.bundlePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
