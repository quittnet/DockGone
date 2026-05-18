import Cocoa
import ApplicationServices

// Per-app accessibility-based attention detection. Public surface:
//   AttentionTracker.shared.start()                – call once at launch
//   AttentionTracker.shared.attentionPIDs          – Set<pid_t> currently flagged
//   AttentionTracker.shared.attentionApps          – sorted list of AttentionInfo
//   AttentionTracker.didChangeNotification         – posts when the set changes
//
// Heuristic: when a window appears in a regular-policy app that is finished
// launching but not currently active, treat it as an attention request (save
// dialogs, "are you sure?" prompts, IDE breakpoints, etc.). This is the
// closest reliable signal available via public API; the real
// requestUserAttention(_:) call isn't exposed via Notification or KVO.
//
// Cleared when:
//   - the app becomes active (NSWorkspaceDidActivateApplicationNotification)
//   - the app terminates
//   - a 5-minute backstop fires (catches edge cases where neither happens)

struct AttentionInfo {
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let appIcon: NSImage?
    let firstSeen: Date
}

final class AttentionTracker {
    static let shared = AttentionTracker()
    static let didChangeNotification = Notification.Name("DockGoneAttentionDidChange")

    private var observers: [pid_t: AXObserver] = [:]
    private var attention: [pid_t: AttentionInfo] = [:]
    private var expiryTimers: [pid_t: Timer] = [:]
    private let backstopInterval: TimeInterval = 300  // 5 minutes
    private var started = false

    private init() {}

    // MARK: - Public

    var attentionPIDs: Set<pid_t> { Set(attention.keys) }

    var attentionApps: [AttentionInfo] {
        attention.values.sorted { $0.firstSeen < $1.firstSeen }
    }

    func start() {
        guard !started else { return }
        started = true

        // Prompt for Accessibility permission. If the user has already granted
        // it, this is a no-op. If not, the system shows a one-time dialog
        // pointing to System Settings — the tracker stays inert until allowed,
        // and starts producing signals the next time DockGone launches.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        for app in NSWorkspace.shared.runningApplications {
            installObserver(for: app)
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(workspaceDidLaunch(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(workspaceDidTerminate(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(workspaceDidActivate(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    // MARK: - AX observer lifecycle

    private func installObserver(for app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        guard pid > 0, observers[pid] == nil else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)
        guard result == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Subscribe to two creation events:
        //   AXWindowCreated — covers detached dialog-style windows
        //   AXSheetCreated  — covers save sheets / alert sheets attached to a window
        // Both are filtered through isAttentionWorthy(_:) below so we only
        // surface sheets and dialog-subrole windows. Plain standard windows
        // (status panels, helper windows, etc.) are ignored.
        let r1 = AXObserverAddNotification(
            observer, appElement, kAXWindowCreatedNotification as CFString, refcon
        )
        _ = AXObserverAddNotification(
            observer, appElement, kAXSheetCreatedNotification as CFString, refcon
        )
        // Some apps reject AX observation entirely (sandboxed helpers, etc.);
        // silently skip them — we just won't catch attention from those apps.
        guard r1 == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(observer),
                           .commonModes)
        observers[pid] = observer
    }

    private func removeObserver(pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              AXObserverGetRunLoopSource(obs),
                              .commonModes)
    }

    // MARK: - Workspace notifications

    @objc private func workspaceDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        installObserver(for: app)
    }

    @objc private func workspaceDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        removeObserver(pid: pid)
        clearAttention(pid: pid)
    }

    @objc private func workspaceDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        clearAttention(pid: app.processIdentifier)
    }

    // MARK: - AX callback handling

    fileprivate func handleAXNotification(name: String, element: AXUIElement) {
        let isWindow = (name == (kAXWindowCreatedNotification as String))
        let isSheet  = (name == (kAXSheetCreatedNotification  as String))
        guard isWindow || isSheet else { return }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              app.isFinishedLaunching,
              !app.isActive
        else { return }

        // Sheet events are intrinsically attention-worthy. Window events
        // need a role/subrole check so helper/utility/status windows don't
        // get flagged.
        if isWindow && !Self.isAttentionWorthyWindow(element) { return }

        markAttention(for: app)
    }

    // Whitelist: only AXSheet (role), or AXDialog / AXSystemDialog (subrole).
    // Everything else — AXStandardWindow, AXFloatingWindow, AXUtilityWindow,
    // unknown — is treated as a normal app window, not an attention signal.
    private static func isAttentionWorthyWindow(_ element: AXUIElement) -> Bool {
        var roleRef:    AnyObject?
        var subroleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let role    = roleRef    as? String ?? ""
        let subrole = subroleRef as? String ?? ""
        if role == (kAXSheetRole as String) { return true }
        if subrole == (kAXDialogSubrole as String) { return true }
        if subrole == (kAXSystemDialogSubrole as String) { return true }
        return false
    }

    private func markAttention(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        let isNew = (attention[pid] == nil)
        attention[pid] = AttentionInfo(
            pid: pid,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "(unknown)",
            appIcon: app.icon,
            firstSeen: attention[pid]?.firstSeen ?? Date()
        )
        scheduleBackstop(for: pid)
        if isNew { post() }
    }

    private func clearAttention(pid: pid_t) {
        guard attention.removeValue(forKey: pid) != nil else { return }
        expiryTimers.removeValue(forKey: pid)?.invalidate()
        post()
    }

    private func scheduleBackstop(for pid: pid_t) {
        expiryTimers[pid]?.invalidate()
        expiryTimers[pid] = Timer.scheduledTimer(
            withTimeInterval: backstopInterval, repeats: false
        ) { [weak self] _ in
            self?.clearAttention(pid: pid)
        }
    }

    private func post() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

// C function pointer — cannot capture context, so the tracker self is
// threaded through the refcon parameter via Unmanaged.passUnretained.
// AttentionTracker is a process-wide singleton so unretained is safe.
private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<AttentionTracker>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    DispatchQueue.main.async {
        tracker.handleAXNotification(name: name, element: element)
    }
}
