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
        // Restore apps concurrently: each one independently launches (if needed),
        // waits up to ~10s for its windows, and repositions them. Done serially
        // that latency would stack — a profile with several cold-launching apps
        // would take tens of seconds. The task index is carried through so the
        // outcomes (and thus the menu's warning list) stay in profile order.
        await withTaskGroup(of: (Int, RestoreOutcome).self) { group in
            for (index, savedApp) in profile.apps.enumerated() {
                group.addTask { (index, await restore(app: savedApp)) }
            }
            var indexed: [(Int, RestoreOutcome)] = []
            for await result in group { indexed.append(result) }
            return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private static func restore(app savedApp: SavedApp) async -> RestoreOutcome {
        // 1. Gather every running instance of this bundle id, launching one if
        //    none exist. Pooling all instances (rather than guessing with .first)
        //    means it doesn't matter which process owns which window when an app
        //    runs more than once — saved windows match against the union.
        var instances = NSRunningApplication.runningApplications(withBundleIdentifier: savedApp.bundleID)
        if instances.isEmpty {
            guard let url = resolveAppURL(for: savedApp) else {
                return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                      warning: "\(savedApp.name) isn't installed — skipped")
            }
            do {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                let launched = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                instances = [launched]
            } catch {
                return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                      warning: "\(savedApp.name) failed to launch — skipped")
            }
        }

        // 2. Wait for the app to publish its standard windows. Restore applies
        //    the same isStandardWindow filter capture used, so a palette or sheet
        //    can neither satisfy the wait nor absorb a saved frame. Newly launched
        //    apps take a beat — poll up to ~10s (heavy apps cold-launch slowly),
        //    then give up gracefully.
        var liveWindows = standardWindows(of: instances)
        var attempts = 0
        while liveWindows.isEmpty && attempts < 40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            liveWindows = standardWindows(of: instances)
            attempts += 1
        }
        guard !liveWindows.isEmpty else {
            return RestoreOutcome(appName: savedApp.name, positioned: 0,
                                  warning: "\(savedApp.name) opened but exposed no windows")
        }

        // 3. Pair saved windows to live windows, then apply each saved frame.
        var positioned = 0
        for (savedWindow, target) in pairings(saved: savedApp.windows, live: liveWindows) {
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

    /// The standard document/app windows pooled across every running instance of
    /// an app — the same filter capture uses, so restore never targets a palette
    /// or sheet, and multiple instances of one bundle id contribute their windows
    /// to a single candidate set.
    private static func standardWindows(of instances: [NSRunningApplication]) -> [AXUIElement] {
        instances.flatMap { app -> [AXUIElement] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            return AX.windows(of: element).filter { AX.isStandardWindow($0) }
        }
    }

    /// Pair each saved window with a live window in two passes: first by exact
    /// title (so reordered windows follow their title), then positionally for
    /// whatever is left over (so a window whose title changed, or that was never
    /// titled, still gets placed in order). Resolving exact matches first means a
    /// titled saved window that finds no match can never steal the window a later
    /// saved window would have matched exactly.
    private static func pairings(saved: [SavedWindow],
                                 live: [AXUIElement]) -> [(SavedWindow, AXUIElement)] {
        var remaining = live
        var pairs: [(SavedWindow, AXUIElement)] = []
        var leftovers: [SavedWindow] = []

        for window in saved {
            if !window.title.isEmpty,
               let index = remaining.firstIndex(where: {
                   AX.string($0, kAXTitleAttribute as String) == window.title
               }) {
                pairs.append((window, remaining.remove(at: index)))
            } else {
                leftovers.append(window)
            }
        }
        for window in leftovers where !remaining.isEmpty {
            pairs.append((window, remaining.removeFirst()))
        }
        return pairs
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
