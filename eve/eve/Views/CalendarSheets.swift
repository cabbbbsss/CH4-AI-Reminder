//
//  CalendarSheets.swift
//  Eve
//
//  Created by cabsss on 09/07/26.
//

import SwiftUI
import SwiftData

/// Edit a calendar reminder's text or remove it. Any edit marks the row
/// user-owned so a reload won't overwrite it.
struct CalendarReminderEditSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var reminder: CalendarReminder
    var manager: CalendarReminderManager?

    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Text", text: $text)
                }

                Section {
                    Text("For \(reminder.eventTitle) at \(reminder.eventDate.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Remove Reminder", role: .destructive) {
                        manager?.remove(reminder)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                text = reminder.text
            }
        }
    }

    private func save() {

        reminder.text = text.trimmingCharacters(in: .whitespaces)
        // Any user edit makes this row theirs — reload must not regenerate it.
        reminder.isSystemManaged = false

        try? modelContext.save()

    }

}

/// Manually add a reminder to a given day. `CalendarReminder.reminderDate`
/// is always `eventDate - 1hr`, so the picked "remind me at" time is stored
/// as `eventDate + 1hr` to make it land exactly where the user placed it.
struct CalendarReminderAddSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The day this reminder is being added to (the Calendar screen's
    /// currently selected date).
    var date: Date

    @State private var text: String = ""
    @State private var eventTitle: String = ""
    @State private var reminderTime: Date

    init(date: Date) {
        self.date = date
        let calendar = Calendar.current
        let defaultHour = calendar.component(.hour, from: .now)
        _reminderTime = State(initialValue: calendar.date(
            bySettingHour: min(defaultHour + 1, 23), minute: 0, second: 0, of: date
        ) ?? date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Text", text: $text)
                }

                Section("For") {
                    TextField("Event title (optional)", text: $eventTitle)
                }

                Section("Time") {
                    DatePicker("Remind me at", selection: $reminderTime, displayedComponents: [.hourAndMinute])
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {

        let calendar = Calendar.current
        let pickedTime = calendar.date(
            bySettingHour: calendar.component(.hour, from: reminderTime),
            minute: calendar.component(.minute, from: reminderTime),
            second: 0,
            of: date
        ) ?? date

        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespaces)

        let reminder = CalendarReminder(
            occurrenceID: "manual-\(UUID().uuidString)",
            eventTitle: trimmedTitle.isEmpty ? "Personal reminder" : trimmedTitle,
            eventDate: pickedTime.addingTimeInterval(3600),
            text: text.trimmingCharacters(in: .whitespaces),
            isSystemManaged: false
        )

        modelContext.insert(reminder)
        try? modelContext.save()

    }

}
