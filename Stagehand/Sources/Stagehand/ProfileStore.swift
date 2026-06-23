import Foundation
import Combine

/// Owns the list of layout profiles and persists them to
/// `~/Library/Application Support/Stagehand/profiles.json`.
///
/// It's an `ObservableObject` so the SwiftUI manager view updates live. The
/// AppKit menu doesn't observe it — it rebuilds from `profiles` on every open
/// (`menuNeedsUpdate`), which always reflects the latest state.
final class ProfileStore: ObservableObject {

    static let shared = ProfileStore()

    @Published private(set) var profiles: [LayoutProfile] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stagehand", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("profiles.json")
        load()
    }

    /// Absolute location of the JSON file — surfaced in the manager window so
    /// users can find (and back up) their profiles.
    var storageURL: URL { fileURL }

    // MARK: Mutations

    /// Save a brand-new profile, or overwrite the apps of an existing one with
    /// the same name (case-insensitive). Returns the stored profile.
    @discardableResult
    func saveProfile(named name: String, apps: [SavedApp]) -> LayoutProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = profiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            profiles[index].apps = apps
            profiles[index].updatedAt = Date()
            persist()
            return profiles[index]
        }
        let profile = LayoutProfile(name: trimmed, apps: apps)
        profiles.append(profile)
        persist()
        return profile
    }

    /// Rename a profile. Rejected (returns false) if the name is blank or would
    /// collide case-insensitively with another profile — `saveProfile` dedupes by
    /// name, so a duplicate would let a later save silently clobber one of them.
    @discardableResult
    func renameProfile(id: UUID, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let collides = profiles.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !collides else { return false }
        profiles[index].name = trimmed
        profiles[index].updatedAt = Date()
        persist()
        return true
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    /// Flag (or unflag) a profile to be auto-restored at startup/login.
    func setOpenAtStartup(id: UUID, _ value: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].openAtStartup = value
        profiles[index].updatedAt = Date()
        persist()
    }

    func profile(id: UUID) -> LayoutProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: Disk I/O

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }  // no file yet
        do {
            profiles = try decoder.decode([LayoutProfile].self, from: data)
        } catch {
            // The file exists but won't parse (corruption, or an incompatible
            // schema from another version). Do NOT start empty and let the next
            // save atomically overwrite it — move it aside first so the user can
            // recover their profiles.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("profiles.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("Stagehand: couldn't decode profiles.json (\(error)); preserved as \(backup.lastPathComponent)")
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Stagehand: failed to persist profiles: \(error)")
        }
    }
}
