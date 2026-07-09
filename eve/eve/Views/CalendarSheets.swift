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
