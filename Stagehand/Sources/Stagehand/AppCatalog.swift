import AppKit

/// One installed application the user can include in a composed layout.
struct CatalogApp: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static func == (lhs: CatalogApp, rhs: CatalogApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Enumerates installed apps so a layout can be composed for apps that aren't
/// running yet. There's no clean public "list all apps" API, so this scans the
/// standard Applications folders (and their immediate subfolders, e.g. Utilities).
enum AppCatalog {

    static func installedApps() -> [CatalogApp] {
        let roots = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [CatalogApp] = []

        func consider(_ url: URL) {
            guard url.pathExtension == "app",
                  let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !seen.contains(bundleID) else { return }
            seen.insert(bundleID)
            let name = url.deletingPathExtension().lastPathComponent
            apps.append(CatalogApp(id: bundleID, name: name, url: url))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let entries = try? fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                if entry.pathExtension == "app" {
                    consider(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // One level deep (e.g. /Applications/Utilities/*.app).
                    let nested = (try? fm.contentsOfDirectory(
                        at: entry, includingPropertiesForKeys: nil)) ?? []
                    for sub in nested where sub.pathExtension == "app" { consider(sub) }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
