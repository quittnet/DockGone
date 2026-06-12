import Foundation
import Observation

/// One recording (or imported file) as it moves through the pipeline:
/// recorded → transcribed → extracted (ready for review).
@MainActor
@Observable
final class CapturedItem: Identifiable {
    let id = UUID()
    let createdAt = Date()
    var title: String
    var audioURL: URL?
    var transcript: String = ""
    var events: [ProposedEvent] = []
    var reminders: [ProposedReminder] = []
    var status: Status = .recorded

    enum Status: Equatable {
        case recorded
        case transcribing
        case extracting
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .recorded: return "Recorded"
            case .transcribing: return "Transcribing…"
            case .extracting: return "Finding events…"
            case .ready: return "Ready to review"
            case .failed(let message): return "Failed: \(message)"
            }
        }

        var isWorking: Bool { self == .transcribing || self == .extracting }
    }

    init(title: String, audioURL: URL?) {
        self.title = title
        self.audioURL = audioURL
    }

    var actionableCount: Int { events.count + reminders.count }
}
