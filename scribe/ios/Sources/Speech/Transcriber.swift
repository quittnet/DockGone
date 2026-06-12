import Foundation
import Speech

/// On-device speech-to-text via the Speech framework. Audio never leaves the
/// phone — only the resulting text is later sent to the backend.
@MainActor
final class Transcriber {
    enum TranscriptionError: LocalizedError {
        case notAuthorized
        case unavailable
        case empty

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition permission was denied."
            case .unavailable: return "On-device speech recognition isn't available for your language."
            case .empty: return "No speech was detected in the recording."
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(url: URL, locale: Locale = .current) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Guard against the recognition callback resuming the continuation twice.
        let guardBox = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if guardBox.tryResume() { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                if guardBox.tryResume() {
                    let text = result.bestTranscription.formattedString
                    if text.isEmpty {
                        continuation.resume(throwing: TranscriptionError.empty)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }
}

/// Tiny thread-safe latch so the speech callback resumes the continuation once.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
