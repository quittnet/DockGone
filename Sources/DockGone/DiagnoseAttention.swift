import Cocoa
import ApplicationServices

// Snapshot of every observable AX signal that AttentionTracker considers.
// Triggered manually from the menu bar when an attention case is on screen
// but the dot didn't light up — the resulting text file is enough to see
// whether the missed app is even AX-visible, and what its windows look like.

enum DiagnoseAttention {
    static func writeReport() {
        var out = ""
        out += "DockGone Attention Diagnostic\n"
        out += "Generated: \(Date())\n"
        out += "AX trusted: \(AXIsProcessTrusted())\n\n"

        out += "== AttentionTracker state ==\n"
        let pids = AttentionTracker.shared.attentionPIDs
        out += "Flagged PIDs: \(pids.isEmpty ? "(none)" : pids.map { String($0) }.joined(separator: ", "))\n"
        for info in AttentionTracker.shared.attentionApps {
            out += "  - \(info.appName) pid=\(info.pid) bundle=\(info.bundleID ?? "?")\n"
        }
        out += "\n"

        out += "== Dock tiles ==\n"
        out += dockTileReport()
        out += "\n"

        out += "== Non-active regular-policy apps ==\n"
        out += nonActiveAppsReport()

        let path = ("~/Desktop/dockgone-diag.txt" as NSString).expandingTildeInPath
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Dock

    private static func dockTileReport() -> String {
        guard let dock = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.dock").first else {
            return "  (Dock process not found)\n"
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = findBiggestList(in: app) else {
            return "  (no AXList child found on Dock)\n"
        }
        guard let tiles = copyAttr(list, kAXChildrenAttribute as String)
                as? [AXUIElement] else {
            return "  (Dock list has no children)\n"
        }
        var s = "  \(tiles.count) tiles\n"
        for (i, tile) in tiles.enumerated() {
            let title = (copyAttr(tile, kAXTitleAttribute as String) as? String) ?? ""
            let url = (copyAttr(tile, kAXURLAttribute as String) as? URL)?.lastPathComponent ?? ""
            let badge = (copyAttr(tile, "AXStatusLabel") as? String) ?? ""
            var namesRef: CFArray?
            AXUIElementCopyAttributeNames(tile, &namesRef)
            let names = (namesRef as? [String]) ?? []
            let interesting = names.filter {
                let l = $0.lowercased()
                return l.contains("attention") || l.contains("bounc")
                    || l.contains("status") || l.contains("running")
                    || l.contains("modif")
            }
            s += "  [\(i)] \(title.isEmpty ? url : title)"
            if !badge.isEmpty { s += "  badge=\"\(badge)\"" }
            s += "\n"
            for name in interesting {
                if let v = copyAttr(tile, name) {
                    s += "      \(name) = \(describe(v))\n"
                }
            }
        }
        return s
    }

    private static func findBiggestList(in app: AXUIElement) -> AXUIElement? {
        guard let children = copyAttr(app, kAXChildrenAttribute as String)
                as? [AXUIElement] else { return nil }
        var best: AXUIElement?
        var bestCount = -1
        for child in children {
            let role = (copyAttr(child, kAXRoleAttribute as String) as? String) ?? ""
            guard role == (kAXListRole as String) else { continue }
            let count = (copyAttr(child, kAXChildrenAttribute as String)
                as? [AXUIElement])?.count ?? 0
            if count > bestCount { best = child; bestCount = count }
        }
        return best
    }

    // MARK: - Apps

    private static func nonActiveAppsReport() -> String {
        var s = ""
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.isFinishedLaunching,
                  !app.isActive else { continue }
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            let fingerprints = AttentionTracker.shared.currentAttentionFingerprints(pid: pid)
            let flagged = AttentionTracker.shared.appHasFlaggableAttentionWindow(pid: pid)
            s += "  \(app.localizedName ?? "?") pid=\(pid) bundle=\(app.bundleIdentifier ?? "?")"
            s += " fingerprints=\(fingerprints.count)"
            s += flagged ? " [FLAGGED]" : ""
            s += "\n"
            let element = AXUIElementCreateApplication(pid)
            guard let windows = copyAttr(element, kAXWindowsAttribute as String)
                    as? [AXUIElement] else {
                s += "      (no AXWindows attribute — AX observation likely blocked)\n"
                continue
            }
            if windows.isEmpty { s += "      (0 windows)\n"; continue }
            for (i, w) in windows.enumerated() {
                s += windowReport(w, label: "window[\(i)]", indent: "      ")
                if let sheets = copyAttr(w, "AXSheets") as? [AXUIElement] {
                    for (j, sh) in sheets.enumerated() {
                        s += windowReport(sh, label: "AXSheets[\(j)]",
                                          indent: "        ")
                    }
                }
                if let children = copyAttr(w, kAXChildrenAttribute as String)
                        as? [AXUIElement] {
                    for (j, c) in children.enumerated() {
                        let role = (copyAttr(c, kAXRoleAttribute as String)
                            as? String) ?? ""
                        if role == (kAXSheetRole as String) {
                            s += windowReport(c, label: "childSheet[\(j)]",
                                              indent: "        ")
                        }
                    }
                }
            }
        }
        return s.isEmpty ? "  (none)\n" : s
    }

    // MARK: - Window inspection

    // Prints a window/sheet element with everything the tracker considers
    // plus a verdict so we can tell at a glance why it was/wasn't flagged.
    private static func windowReport(_ w: AXUIElement,
                                     label: String,
                                     indent: String) -> String {
        let role = (copyAttr(w, kAXRoleAttribute as String) as? String) ?? ""
        let subrole = (copyAttr(w, kAXSubroleAttribute as String) as? String) ?? ""
        let title = (copyAttr(w, kAXTitleAttribute as String) as? String) ?? ""
        let modal = (copyAttr(w, kAXModalAttribute as String) as? Bool) ?? false
        let frame = windowFrame(w)
        let frameStr = frame.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" }
            ?? "?"
        let buttons = buttonDescendantCount(w, maxDepth: 3)
        let verdict = AttentionTracker.shared.isRealAttentionSurface(w)
            ? " → FLAGGED" : ""
        var s = "\(indent)\(label) role=\(role) subrole=\(subrole) modal=\(modal) "
        s += "frame=\(frameStr) buttons=\(buttons) title=\"\(title)\"\(verdict)\n"
        return s
    }

    private static func windowFrame(_ w: AXUIElement) -> CGRect? {
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

    private static func buttonDescendantCount(_ element: AXUIElement,
                                              maxDepth: Int) -> Int {
        guard maxDepth > 0,
              let children = copyAttr(element, kAXChildrenAttribute as String)
                as? [AXUIElement] else { return 0 }
        var n = 0
        for c in children {
            if (copyAttr(c, kAXRoleAttribute as String) as? String)
                == (kAXButtonRole as String) { n += 1 }
            n += buttonDescendantCount(c, maxDepth: maxDepth - 1)
        }
        return n
    }

    // MARK: - Utilities

    private static func copyAttr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var out: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &out) == .success
            ? out : nil
    }

    private static func describe(_ v: AnyObject) -> String {
        if let b = v as? Bool { return String(b) }
        if let n = v as? NSNumber { return n.stringValue }
        if let s = v as? String { return "\"\(s)\"" }
        return String(describing: v)
    }
}
