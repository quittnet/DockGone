import Foundation

/// These types mirror `scribe/backend/src/schema.ts` exactly. If the backend
/// schema changes, change these too — they are the wire contract.

enum ReminderPriority: String, Codable, CaseIterable, Identifiable {
    case none, low, medium, high

    var id: String { rawValue }

    var display: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// EventKit uses an Int priority: 0 = none, 1 = highest, 5 = medium, 9 = lowest.
    var ekPriority: Int {
        switch self {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }
}

struct ProposedEvent: Codable, Identifiable {
    var id = UUID()
    var title: String
    var start: String          // ISO-8601 local date-time, no timezone suffix
    var end: String?
    var allDay: Bool
    var location: String?
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case title, start, end, allDay, location, notes
    }
}

struct ProposedReminder: Codable, Identifiable {
    var id = UUID()
    var title: String
    var dueDate: String?       // ISO-8601 local date-time, no timezone suffix
    var notes: String?
    var priority: ReminderPriority

    private enum CodingKeys: String, CodingKey {
        case title, dueDate, notes, priority
    }
}

/// Top-level response shape of `POST /extract`.
struct ExtractionResult: Codable {
    var events: [ProposedEvent]
    var reminders: [ProposedReminder]
}

/// Parses the backend's "local, no timezone" date-time strings into `Date`,
/// interpreting them in the device's current calendar/timezone.
enum LocalDateTime {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return formatter.date(from: string)
    }
}
