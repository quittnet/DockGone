import SwiftUI
import Observation

struct ReviewView: View {
    let item: CapturedItem
    var onRetry: () async -> Void

    @State private var events: [EditableEvent] = []
    @State private var reminders: [EditableReminder] = []
    @State private var loaded = false
    @State private var isSaving = false
    @State private var resultMessage: String?

    private let eventKit = EventKitService()

    var body: some View {
        Form {
            switch item.status {
            case .transcribing, .extracting:
                Section {
                    HStack {
                        ProgressView()
                        Text(item.status.label).foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await onRetry() } }
                }
            default:
                EmptyView()
            }

            if !item.transcript.isEmpty {
                Section("Transcript") {
                    Text(item.transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !events.isEmpty {
                Section("Events") {
                    ForEach(events) { event in
                        EventEditor(event: event)
                    }
                }
            }

            if !reminders.isEmpty {
                Section("Reminders") {
                    ForEach(reminders) { reminder in
                        ReminderEditor(reminder: reminder)
                    }
                }
            }

            if item.status == .ready && events.isEmpty && reminders.isEmpty {
                Section {
                    Text("Scribe didn't find any events or reminders in this recording.")
                        .foregroundStyle(.secondary)
                }
            }

            if !events.isEmpty || !reminders.isEmpty {
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Add selected to Calendar & Reminders")
                        }
                    }
                    .disabled(isSaving || selectedCount == 0)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: item.status) { _, _ in loadIfNeeded() }
        .alert(
            "Done",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var selectedCount: Int {
        events.filter(\.include).count + reminders.filter(\.include).count
    }

    private func loadIfNeeded() {
        guard !loaded, item.status == .ready else { return }
        events = item.events.map(EditableEvent.init)
        reminders = item.reminders.map(EditableReminder.init)
        loaded = true
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let chosenEvents = events.filter(\.include)
        let chosenReminders = reminders.filter(\.include)

        do {
            if !chosenEvents.isEmpty {
                guard try await eventKit.requestCalendarAccess() else {
                    resultMessage = "Calendar access was denied. Enable it in Settings to add events."
                    return
                }
                for event in chosenEvents {
                    try eventKit.addEvent(
                        title: event.title,
                        start: event.start,
                        end: event.hasEnd ? event.end : nil,
                        allDay: event.allDay,
                        location: event.location.isEmpty ? nil : event.location,
                        notes: event.notes.isEmpty ? nil : event.notes
                    )
                }
            }

            if !chosenReminders.isEmpty {
                guard try await eventKit.requestRemindersAccess() else {
                    resultMessage = "Reminders access was denied. Enable it in Settings to add reminders."
                    return
                }
                for reminder in chosenReminders {
                    try eventKit.addReminder(
                        title: reminder.title,
                        due: reminder.hasDue ? reminder.due : nil,
                        notes: reminder.notes.isEmpty ? nil : reminder.notes,
                        priority: reminder.priority
                    )
                }
            }

            resultMessage = "Added \(chosenEvents.count) event(s) and \(chosenReminders.count) reminder(s)."
        } catch {
            resultMessage = "Couldn't add everything: \(error.localizedDescription)"
        }
    }
}

// MARK: - Editable models

@Observable
final class EditableEvent: Identifiable {
    let id = UUID()
    var include = true
    var title: String
    var start: Date
    var end: Date
    var hasEnd: Bool
    var allDay: Bool
    var location: String
    var notes: String

    init(_ proposal: ProposedEvent) {
        title = proposal.title
        let startDate = LocalDateTime.date(from: proposal.start) ?? Date()
        start = startDate
        if let endDate = LocalDateTime.date(from: proposal.end) {
            end = endDate
            hasEnd = true
        } else {
            end = startDate.addingTimeInterval(3600)
            hasEnd = false
        }
        allDay = proposal.allDay
        location = proposal.location ?? ""
        notes = proposal.notes ?? ""
    }
}

@Observable
final class EditableReminder: Identifiable {
    let id = UUID()
    var include = true
    var title: String
    var due: Date
    var hasDue: Bool
    var notes: String
    var priority: ReminderPriority

    init(_ proposal: ProposedReminder) {
        title = proposal.title
        if let dueDate = LocalDateTime.date(from: proposal.dueDate) {
            due = dueDate
            hasDue = true
        } else {
            due = Date()
            hasDue = false
        }
        notes = proposal.notes ?? ""
        priority = proposal.priority
    }
}

// MARK: - Row editors

private struct EventEditor: View {
    @Bindable var event: EditableEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $event.include) {
                TextField("Title", text: $event.title)
                    .font(.headline)
            }
            Toggle("All-day", isOn: $event.allDay)
            DatePicker("Starts", selection: $event.start,
                       displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
            Toggle("Has end time", isOn: $event.hasEnd)
            if event.hasEnd {
                DatePicker("Ends", selection: $event.end,
                           displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
            }
            TextField("Location", text: $event.location)
            TextField("Notes", text: $event.notes, axis: .vertical)
        }
        .opacity(event.include ? 1 : 0.5)
    }
}

private struct ReminderEditor: View {
    @Bindable var reminder: EditableReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $reminder.include) {
                TextField("Title", text: $reminder.title)
                    .font(.headline)
            }
            Toggle("Has due date", isOn: $reminder.hasDue)
            if reminder.hasDue {
                DatePicker("Due", selection: $reminder.due,
                           displayedComponents: [.date, .hourAndMinute])
            }
            Picker("Priority", selection: $reminder.priority) {
                ForEach(ReminderPriority.allCases) { priority in
                    Text(priority.display).tag(priority)
                }
            }
            TextField("Notes", text: $reminder.notes, axis: .vertical)
        }
        .opacity(reminder.include ? 1 : 0.5)
    }
}
