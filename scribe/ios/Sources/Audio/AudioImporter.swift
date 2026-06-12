import Foundation

/// Copies a user-picked audio file (from Files / share sheet) into the app's
/// Documents directory, handling the security-scoped resource dance.
enum AudioImporter {
    static func importToAppStorage(from source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let destination = docs.appendingPathComponent("import-\(UUID().uuidString).\(ext)")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
