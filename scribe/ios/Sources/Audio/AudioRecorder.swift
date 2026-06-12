import Foundation
import AVFoundation
import Observation

/// Thin wrapper around `AVAudioRecorder` that records to an .m4a file in the
/// app's Documents directory.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    enum RecorderError: LocalizedError {
        case sessionFailed(String)

        var errorDescription: String? {
            switch self {
            case .sessionFailed(let message): return message
            }
        }
    }

    /// Requests microphone permission (iOS 17 API). Returns true if granted.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Begins recording. Returns the destination URL.
    @discardableResult
    func start() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            throw RecorderError.sessionFailed(error.localizedDescription)
        }

        let url = Self.makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        self.recorder = recorder
        self.currentURL = url
        isRecording = true
        return url
    }

    /// Stops recording and returns the file URL (or nil if not recording).
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        let url = currentURL
        currentURL = nil
        return url
    }

    private static func makeRecordingURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return docs.appendingPathComponent("recording-\(stamp).m4a")
    }
}
