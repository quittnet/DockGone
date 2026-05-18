import Cocoa

struct DockApp {
    enum Kind {
        case app     // launch via NSWorkspace.openApplication
        case folder  // reveal via NSWorkspace.open
        case close   // no-op: selecting just dismisses the switcher
    }

    let name: String
    let url: URL
    let icon: NSImage
    var kind: Kind = .app
    // Non-nil when this Dock app is currently requesting user attention.
    // The switcher uses it to (a) draw the attention glow ring and
    // (b) activate the existing process instead of launching a new one.
    var attentionPID: pid_t? = nil
}

enum DockReader {
    // attentionApps: running apps currently flagged by AttentionTracker.
    // Their bundle IDs bypass the running-filter so the user can click their
    // tile in the switcher to bring the existing process forward (e.g., to
    // dismiss a save dialog). Each surviving entry carries the matching pid.
    static func getUnopenedApps(attentionApps: [AttentionInfo] = []) -> [DockApp] {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let persistentApps = plist["persistent-apps"] as? [[String: Any]]
        else { return [] }

        // Map: bundleID -> pid for apps that are attention-pending.
        var attentionByBundleID: [String: pid_t] = [:]
        for info in attentionApps {
            if let bid = info.bundleID { attentionByBundleID[bid] = info.pid }
        }

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleIdentifier }
        )

        return persistentApps.compactMap { appDict -> DockApp? in
            guard
                let tileData = appDict["tile-data"] as? [String: Any],
                let fileData = tileData["file-data"] as? [String: Any],
                let urlString = fileData["_CFURLString"] as? String,
                (appDict["tile-type"] as? String ?? "file-tile") == "file-tile"
            else { return nil }

            let url: URL? = urlString.hasPrefix("file://")
                ? URL(string: urlString)
                : URL(fileURLWithPath: urlString)

            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }

            let bundleID = Bundle(url: url)?.bundleIdentifier
            let attentionPID = bundleID.flatMap { attentionByBundleID[$0] }

            // Running apps are normally filtered out, but attention-pending
            // ones are kept so the user can click to activate them.
            if attentionPID == nil,
               let bid = bundleID, runningBundleIDs.contains(bid) {
                return nil
            }

            let name = tileData["file-label"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)

            return DockApp(name: name, url: url, icon: icon, attentionPID: attentionPID)
        }
    }

    // Trash bin "tile" — always appended to the end of the switcher list.
    // Picks the full or empty trash icon based on whether ~/.Trash has items;
    // opening it asks Finder to reveal the Trash folder.
    static func getTrashEntry() -> DockApp {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
        let items = (try? FileManager.default.contentsOfDirectory(
            atPath: trashURL.path)) ?? []
        let nonHidden = items.filter { !$0.hasPrefix(".") }
        let iconName: NSImage.Name = nonHidden.isEmpty
            ? NSImage.Name("NSTrashEmpty")
            : NSImage.Name("NSTrashFull")
        let icon = NSImage(named: iconName)
            ?? NSWorkspace.shared.icon(forFile: trashURL.path)
        return DockApp(name: "Trash", url: trashURL, icon: icon, kind: .folder)
    }

    // "Close" tile rendered as a filled X mark. Selecting it just dismisses
    // the switcher; the URL is a placeholder and never opened. Sized to the
    // current icon size so the symbol scales with the rest of the strip.
    static func getCloseEntry(size: CGFloat) -> DockApp {
        let pt = max(20, size * 0.78)
        let conf = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
        let img = NSImage(systemSymbolName: "xmark.circle.fill",
                          accessibilityDescription: "Close")?
            .withSymbolConfiguration(conf) ?? NSImage()
        img.isTemplate = true
        return DockApp(name: "Close",
                       url: URL(fileURLWithPath: "/dev/null"),
                       icon: img,
                       kind: .close)
    }

    static func getAllAppsNotInDock() -> [DockApp] {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

        // Match against the Dock by bundle identifier first (robust to symlinks
        // and path-string variations), and by normalized path as a fallback.
        var dockBundleIDs = Set<String>()
        var dockPaths     = Set<String>()
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let persistentApps = plist["persistent-apps"] as? [[String: Any]] {
            for appDict in persistentApps {
                guard
                    let tileData = appDict["tile-data"] as? [String: Any],
                    let fileData = tileData["file-data"] as? [String: Any],
                    let urlStr = fileData["_CFURLString"] as? String
                else { continue }
                let url = urlStr.hasPrefix("file://")
                    ? URL(string: urlStr)
                    : URL(fileURLWithPath: urlStr)
                guard let url else { continue }
                dockPaths.insert(canonicalPath(url))
                if let bid = Bundle(url: url)?.bundleIdentifier {
                    dockBundleIDs.insert(bid)
                }
            }
        }

        let fm = FileManager.default
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var result: [DockApp] = []
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                if dockPaths.contains(canonicalPath(url)) { continue }
                if let bid = Bundle(url: url)?.bundleIdentifier,
                   dockBundleIDs.contains(bid) { continue }
                let name = url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                result.append(DockApp(name: name, url: url, icon: icon))
            }
        }

        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // Resolve symlinks, drop any trailing slash, lowercase. Lets us compare
    // Dock plist URL strings against filesystem-enumeration URLs reliably.
    private static func canonicalPath(_ url: URL) -> String {
        var p = url.resolvingSymlinksInPath().path
        while p.hasSuffix("/") { p.removeLast() }
        return p.lowercased()
    }

    static func getDockApps() -> [DockApp] {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let persistentApps = plist["persistent-apps"] as? [[String: Any]]
        else { return [] }

        return persistentApps.compactMap { appDict -> DockApp? in
            guard
                let tileData = appDict["tile-data"] as? [String: Any],
                let fileData = tileData["file-data"] as? [String: Any],
                let urlStr = fileData["_CFURLString"] as? String,
                (appDict["tile-type"] as? String ?? "file-tile") == "file-tile"
            else { return nil }

            let url: URL? = urlStr.hasPrefix("file://")
                ? URL(string: urlStr)
                : URL(fileURLWithPath: urlStr)
            guard let url else { return nil }

            let name = tileData["file-label"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            // Don't gate on fileExists — stale Dock entries (deleted app) should
            // still be selectable so the user can remove them.
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return DockApp(name: name, url: url, icon: icon)
        }
    }

    // Persists the given apps as the new persistent-apps list, preserving
    // each app's original plist entry (so display modes, badges, etc. survive).
    // Handles both reorder (same set, new order) and delete (subset).
    static func saveDockApps(_ apps: [DockApp]) {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            var plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let persistentApps = plist["persistent-apps"] as? [[String: Any]]
        else { return }

        var entryByPath: [String: [String: Any]] = [:]
        for entry in persistentApps {
            guard
                let tileData = entry["tile-data"] as? [String: Any],
                let fileData = tileData["file-data"] as? [String: Any],
                let urlStr   = fileData["_CFURLString"] as? String
            else { continue }
            let url = urlStr.hasPrefix("file://")
                ? URL(string: urlStr)
                : URL(fileURLWithPath: urlStr)
            guard let url else { continue }
            entryByPath[canonicalPath(url)] = entry
        }

        let newEntries = apps.compactMap { entryByPath[canonicalPath($0.url)] }
        plist["persistent-apps"] = newEntries

        if let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? newData.write(to: plistURL)
            killall("Dock")
        }
    }

    static func addAppsToDock(_ apps: [DockApp]) {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            var plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            var persistentApps = plist["persistent-apps"] as? [[String: Any]]
        else { return }

        for app in apps {
            let absStr = app.url.absoluteString
            let urlStr = absStr.hasSuffix("/") ? absStr : absStr + "/"
            let entry: [String: Any] = [
                "tile-type": "file-tile",
                "tile-data": [
                    "file-label": app.name,
                    "file-type": 41,
                    "file-data": [
                        "_CFURLString": urlStr,
                        "_CFURLStringType": 15
                    ] as [String: Any]
                ] as [String: Any]
            ]
            persistentApps.append(entry)
        }

        plist["persistent-apps"] = persistentApps
        if let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? newData.write(to: plistURL)
            killall("Dock")
        }
    }

    private static func killall(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = [name]
        try? p.run()
    }
}
