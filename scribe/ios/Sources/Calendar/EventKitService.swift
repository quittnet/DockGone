import Foundation
import EventKit

/// Requests access to and writes into Apple Calendar and Reminders via EventKit.
@MainActor
final class EventKitService {
    private let store = EKEventStore()

    enum EventKitError: LocalizedError {
        case noDefaultCalendar
        case noDefaultReminderList

        var errorDescription: String? {
            switch self {
            case .noDefaultCalendar: return "No default calendar is configured on this device."
            case .noDefaultReminderList: return "No default reminders list is configured on this device."
            }
        }
    }

    func requestCalendarAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func requestRemindersAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    func addEvent(
        title: String,
        start: Date,
        end: Date?,
        allDay: Bool,
        location: String?,
        notes: String?
    ) throws {
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw EventKitError.noDefaultCalendar
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(3600)
        event.location = location
        event.notes = notes
        event.calendar = calendar
        if !allDay {
            event.addAlarm(EKAlarm(relativeOffset: -15 * 60))
        }
        try store.save(event, span: .thisEvent, commit: true)
    }

    func addReminder(
        title: String,
        due: Date?,
        notes: String?,
        priority: ReminderPriority
    ) throws {
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw EventKitError.noDefaultReminderList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority.ekPriority
        reminder.calendar = calendar
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
    }
}
