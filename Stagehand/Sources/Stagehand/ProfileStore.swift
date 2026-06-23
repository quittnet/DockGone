import Foundation
import Combine

/// Owns the list of layout profiles and persists them to
/// `~/Library/Application Support/Stagehand/profiles.json`.
///
/// It's an `ObservableObject` so the SwiftUI manager view updates live, and it
/// also posts `didChange` for the AppKit menu, which rebuilds itself on open.
final class ProfileStore: ObservableObject {

    static let shared = ProfileStore()

    static let didChange = Notification.Name("ProfileStore.didChange")

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

    /// Absolute path to the JSON file — shown in the UI so users can find it.
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

    /// Replace the captured layout of an existing profile (by id) with `apps`.
    func updateProfile(id: UUID, apps: [SavedApp]) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].apps = apps
        profiles[index].updatedAt = Date()
        persist()
    }

    func renameProfile(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        profiles[index].updatedAt = Date()
        persist()
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    func profile(id: UUID) -> LayoutProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: Disk I/O

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([LayoutProfile].self, from: data) {
            profiles = decoded
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Stagehand: failed to persist profiles: \(error)")
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
