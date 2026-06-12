import Foundation
import Observation

/// UserDefaults key shared with `SettingsView` (`@AppStorage("backendURL")`).
let backendURLDefaultsKey = "backendURL"

/// Orchestrates the capture pipeline and owns the list of captures shown in the UI.
@MainActor
@Observable
final class CaptureStore {
    var items: [CapturedItem] = []
    var permissionMessage: String?

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()

    var isRecording: Bool { recorder.isRecording }

    private var backendURL: URL? {
        let raw = UserDefaults.standard.string(forKey: backendURLDefaultsKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    // MARK: Recording

    func toggleRecording() async {
        if recorder.isRecording {
            await stopAndProcess()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard await recorder.requestPermission() else {
            permissionMessage = "Microphone access is required to record. Enable it in Settings."
            return
        }
        guard await transcriber.requestAuthorization() else {
            permissionMessage = "Speech recognition access is required to transcribe. Enable it in Settings."
            return
        }
        do {
            try recorder.start()
        } catch {
            permissionMessage = error.localizedDescription
        }
    }

    private func stopAndProcess() async {
        guard let url = recorder.stop() else { return }
        let item = CapturedItem(title: defaultTitle(), audioURL: url)
        items.insert(item, at: 0)
        await process(item)
    }

    // MARK: Import

    func importAudio(from source: URL) async {
        do {
            let stored = try AudioImporter.importToAppStorage(from: source)
            guard await transcriber.requestAuthorization() else {
                permissionMessage = "Speech recognition access is required to transcribe."
                return
            }
            let title = source.deletingPathExtension().lastPathComponent
            let item = CapturedItem(title: title.isEmpty ? defaultTitle() : title, audioURL: stored)
            items.insert(item, at: 0)
            await process(item)
        } catch {
            permissionMessage = "Couldn't import that file: \(error.localizedDescription)"
        }
    }

    // MARK: Pipeline

    /// Transcribe on-device, then ask the backend to extract events/reminders.
    func process(_ item: CapturedItem) async {
        guard let url = item.audioURL else {
            item.status = .failed("Missing audio file")
            return
        }
        item.status = .transcribing
        do {
            let transcript = try await transcriber.transcribe(url: url)
            item.transcript = transcript

            guard let base = backendURL else {
                item.status = .failed("Set your backend URL in Settings, then retry.")
                return
            }
            item.status = .extracting
            let client = ExtractionClient(baseURL: base)
            let result = try await client.extract(transcript: transcript)
            item.events = result.events
            item.reminders = result.reminders
            item.status = .ready
        } catch {
            item.status = .failed(error.localizedDescription)
        }
    }

    /// Re-run the pipeline for an item that previously failed.
    func retry(_ item: CapturedItem) async {
        await process(item)
    }

    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
