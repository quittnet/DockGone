import Cocoa
import ApplicationServices

// Polling attention detection. Public surface unchanged:
//   AttentionTracker.shared.start()                 – call once at launch
//   AttentionTracker.shared.attentionPIDs           – Set<pid_t> currently flagged
//   AttentionTracker.shared.attentionApps           – sorted list of AttentionInfo
//   AttentionTracker.didChangeNotification          – posts when the set changes
//
// Single detection rule: an app gets flagged iff it has put up a modal
// dialog/sheet that wasn't already visible the first time we observed it.
// That covers the "unsaved-changes save prompt on quit" case — the dock-
// bouncing replacement we exist to provide. Badges (unread mail, message
// counts, etc.) are deliberately NOT a signal here — DockGone's job is to
// surface the things that block work, not to mirror notification counts.
//
// Every 5 seconds we re-walk the AX tree from scratch — no cached element
// references — and emit a change if the flagged set differs from last tick.

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

    // MARK: - Public

    var attentionPIDs: Set<pid_t> { Set(attention.keys) }

    var attentionApps: [AttentionInfo] {
        attention.values.sorted { $0.firstSeen < $1.firstSeen }
    }

    func start() {
        guard !started else { return }
        started = true

        // Prompt for Accessibility permission. If denied, every AX call
        // silently returns failure and the tracker produces no signals.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(workspaceDidActivate(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(workspaceDidTerminate(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Screen lock observers — Timer.scheduledTimer pauses naturally while
        // the system sleeps, but it keeps firing while the screen is just
        // locked. The AX rescan is wasted work in that state (the user can't
        // see badges anyway) and prevents the CPU from settling into deeper
        // idle states. Resume on unlock.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        startRescanTimer()
        rescan()
    }

    private func startRescanTimer() {
        rescanTimer?.invalidate()
        // 5s is the sweet spot: badge updates from Mail/WhatsApp typically take
        // 1-3s to render in the Dock anyway, and 5s is well below the human
        // "did I see that?" threshold while halving the AX-IPC traffic vs. 2s.
        // Each tick re-walks the Dock + every non-active regular-policy app.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in self?.rescan()
        }
    }

    @objc private func screenLocked() {
        rescanTimer?.invalidate()
        rescanTimer = nil
    }

    @objc private func screenUnlocked() {
        guard started, rescanTimer == nil else { return }
        startRescanTimer()
        rescan()
    }

    // MARK: - Private state

    private var started = false
    private var attention: [pid_t: AttentionInfo] = [:]
    private var rescanTimer: Timer?
    // Per-pid baseline: the set of attention-window fingerprints we saw the
    // first time we observed each process. These are treated as phantom
    // helpers (Office's invisible AXDialog), never flagged. Anything that
    // appears later is new and gets flagged. Cleared when the app quits.
    private var processBaseline: [pid_t: Set<String>] = [:]

    private init() {}

    // MARK: - Workspace notifications

    @objc private func workspaceDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        clearAttention(pid: app.processIdentifier)
    }

    @objc private func workspaceDidTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        processBaseline.removeValue(forKey: pid)
        clearAttention(pid: pid)
    }

    // MARK: - Rescan

    private func rescan() {
        var fresh: [pid_t: AttentionInfo] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.isFinishedLaunching,
                  !app.isActive
            else { continue }
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            if appHasFlaggableAttentionWindow(pid: pid) {
                record(app: app, into: &fresh)
            }
        }

        let oldKeys = Set(attention.keys)
        let newKeys = Set(fresh.keys)
        attention = fresh
        if oldKeys != newKeys { post() }
    }

    private func record(app: NSRunningApplication,
                        into fresh: inout [pid_t: AttentionInfo]) {
        let pid = app.processIdentifier
        fresh[pid] = AttentionInfo(
            pid: pid,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "(unknown)",
            appIcon: app.icon,
            firstSeen: attention[pid]?.firstSeen ?? Date()
        )
    }

    // MARK: - Per-app window walk

    // True if this app has any attention-shaped window that wasn't present
    // the first time we observed the process. The first observation captures
    // the baseline (phantom helpers); anything new is the user-relevant case.
    func appHasFlaggableAttentionWindow(pid: pid_t) -> Bool {
        let current = currentAttentionFingerprints(pid: pid)
        if let baseline = processBaseline[pid] {
            return !current.subtracting(baseline).isEmpty
        }
        // First sight: bank everything currently visible as the phantom set.
        processBaseline[pid] = current
        return false
    }

    // Collect a stable fingerprint of every window/sheet on this app that
    // looks structurally like an attention surface. Fingerprint includes
    // size (Office phantoms have fixed sizes, real save dialogs vary) so a
    // real prompt with the same role/subrole as a phantom still hashes
    // differently and bypasses the baseline.
    func currentAttentionFingerprints(pid: pid_t) -> Set<String> {
        var fps: Set<String> = []
        let element = AXUIElementCreateApplication(pid)
        guard let windows = copyAttr(element, kAXWindowsAttribute as String)
                as? [AXUIElement] else { return fps }
        for w in windows {
            if isRealAttentionSurface(w), let fp = fingerprint(for: w) {
                fps.insert(fp)
            }
            if let sheets = copyAttr(w, "AXSheets") as? [AXUIElement] {
                for s in sheets where isRealAttentionSurface(s) {
                    if let fp = fingerprint(for: s) { fps.insert(fp) }
                }
            }
            if let children = copyAttr(w, kAXChildrenAttribute as String)
                    as? [AXUIElement] {
                for c in children {
                    let role = (copyAttr(c, kAXRoleAttribute as String)
                        as? String) ?? ""
                    if role == (kAXSheetRole as String),
                       isRealAttentionSurface(c),
                       let fp = fingerprint(for: c) { fps.insert(fp) }
                }
            }
        }
        return fps
    }

    private func fingerprint(for w: AXUIElement) -> String? {
        let role = (copyAttr(w, kAXRoleAttribute as String) as? String) ?? ""
        let subrole = (copyAttr(w, kAXSubroleAttribute as String) as? String) ?? ""
        let title = (copyAttr(w, kAXTitleAttribute as String) as? String) ?? ""
        let size = windowFrame(w).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        return "\(role)|\(subrole)|\(title)|\(size)"
    }

    // A window/sheet is a real attention surface iff:
    //   1. Its role is AXSheet, OR its subrole is AXDialog / AXSystemDialog
    //      AND it's modal. The modal requirement matters because Microsoft
    //      Word labels its main document window subrole=AXDialog modal=false
    //      — that's a Word quirk, not an attention request. Real save / quit /
    //      alert prompts are always modal=true.
    //   2. It has a visible frame on at least one screen.
    //   3. It has at least one AXButton descendant.
    func isRealAttentionSurface(_ w: AXUIElement) -> Bool {
        let role = (copyAttr(w, kAXRoleAttribute as String) as? String) ?? ""
        let subrole = (copyAttr(w, kAXSubroleAttribute as String) as? String) ?? ""
        let isSheet = role == (kAXSheetRole as String)
        let isDialog = subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String)
        guard isSheet || isDialog else { return false }
        if isDialog && !isSheet {
            let modal = (copyAttr(w, kAXModalAttribute as String) as? Bool) ?? false
            guard modal else { return false }
        }

        if let frame = windowFrame(w) {
            if frame.width < 80 || frame.height < 40 { return false }
            if !frameIsOnScreen(frame) { return false }
        } else {
            if !isSheet { return false }
        }
        return hasButtonDescendant(w, maxDepth: 3)
    }

    private func windowFrame(_ w: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        let pr = AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef)
        let sr = AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef)
        guard pr == .success, sr == .success,
              let posValue = posRef, let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func frameIsOnScreen(_ frame: CGRect) -> Bool {
        // AX positions are in screen coordinates with origin at the top-left
        // of the primary display; NSScreen uses Cartesian with origin at the
        // bottom-left. Comparing widths/heights and a small intersection
        // tolerance is enough for the phantom check — we don't need precision.
        for screen in NSScreen.screens {
            let s = screen.frame
            // Reject windows wholly off any screen's bounding box.
            if frame.maxX > s.minX, frame.minX < s.maxX,
               frame.maxY > s.minY - 4000, frame.minY < s.maxY + 4000 {
                return true
            }
        }
        return false
    }

    private func hasButtonDescendant(_ element: AXUIElement, maxDepth: Int) -> Bool {
        guard maxDepth > 0,
              let children = copyAttr(element, kAXChildrenAttribute as String)
                as? [AXUIElement] else { return false }
        for c in children {
            if (copyAttr(c, kAXRoleAttribute as String) as? String)
                == (kAXButtonRole as String) { return true }
            if hasButtonDescendant(c, maxDepth: maxDepth - 1) { return true }
        }
        return false
    }

    // MARK: - Utilities

    private func copyAttr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var out: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &out) == .success
            ? out : nil
    }

    private func clearAttention(pid: pid_t) {
        guard attention.removeValue(forKey: pid) != nil else { return }
        post()
    }

    private func post() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
