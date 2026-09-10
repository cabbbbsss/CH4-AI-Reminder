//
//  LocationSheets.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import SwiftUI
import SwiftData

/// Add or edit a saved place's name/address. `location == nil` means add.
struct LocationEditSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var location: SavedLocation?
    var nextSortOrder: Int = 0

    @State private var name: String = ""
    @State private var address: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    TextField("Name", text: $name)
                    TextField("Address (optional)", text: $address, axis: .vertical)
                }
            }
            .navigationTitle(location == nil ? "Add Location" : "Edit Location")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = location?.name ?? ""
                address = location?.address ?? ""
            }
        }
    }

    private func save() {

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        if let location {
            location.name = trimmedName
            location.address = trimmedAddress.isEmpty ? nil : trimmedAddress
        } else {
            modelContext.insert(
                SavedLocation(
                    name: trimmedName,
                    address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                    iconName: "mappin.and.ellipse",
                    isDefault: false,
                    sortOrder: nextSortOrder
                )
            )
        }

        try? modelContext.save()

    }

}

/// Edit a reminder's text, move it to a different place, or remove it.
/// Any edit marks the row user-owned so a refresh won't overwrite it.
struct ReminderEditSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The reminder being edited, or nil when this is a new one — mirroring
    /// `ReminderDetailsView`, so adding and editing are the same screen here
    /// too rather than an inline field that can only set the text.
    var reminder: LocationReminder?

    /// The place a new reminder belongs to.
    var location: SavedLocation?

    /// The day heading a new reminder was added under.
    var defaultDay: Date = .now

    var allLocations: [SavedLocation]
    var router: LocationRoutingManager?

    @State private var text: String = ""
    @State private var selectedLocationID: UUID?
    @State private var trigger: LocationTrigger = .arriving
    @State private var dueDate: Date = .now

    private var isNew: Bool { reminder == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Text", text: $text)
                }

                Section("Location") {
                    Picker("Location", selection: $selectedLocationID) {
                        ForEach(allLocations) { place in
                            Text(place.name).tag(Optional(place.id))
                        }
                    }

                    Picker("Remind me when", selection: $trigger) {
                        ForEach(LocationTrigger.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Day") {
                    DatePicker(
                        "Applies on",
                        selection: $dueDate,
                        displayedComponents: .date
                    )

                    // Says plainly what the date does, since a place-based
                    // reminder having a day at all is not obvious.
                    Text("Eve stops raising this once the day has passed.")
                        .font(.eveDetail)
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                }

                if let reminder {
                    Section {
                        Button("Remove Reminder", role: .destructive) {
                            router?.remove(reminder)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let reminder else {
            selectedLocationID = location?.id ?? allLocations.first?.id
            dueDate = defaultDay
            return
        }
        text = reminder.text
        selectedLocationID = reminder.locationID
        trigger = reminder.trigger
        dueDate = reminder.effectiveDate
    }

    private func save() {

        let trimmed = text.trimmingCharacters(in: .whitespaces)

        guard let reminder else {
            guard let locationID = selectedLocationID ?? location?.id else { return }

            let created = LocationReminder(
                locationID: locationID,
                text: trimmed,
                itemKey: nil,
                isSystemManaged: false
            )
            created.trigger = trigger
            created.dueDate = dueDate

            modelContext.insert(created)
            try? modelContext.save()
            return
        }

        let originalLocationID = reminder.locationID

        reminder.text = trimmed
        reminder.trigger = trigger
        reminder.dueDate = dueDate
        // Any user edit makes this row theirs — refresh must not regenerate it.
        reminder.isSystemManaged = false

        if let selectedLocationID,
           selectedLocationID != originalLocationID,
           let newLocation = allLocations.first(where: { $0.id == selectedLocationID }) {

            reminder.locationID = selectedLocationID

            if let eventTitle = reminder.eventTitle {
                // Moves every other reminder generated from the same
                // calendar event too, so they don't stay scattered across
                // cards, and keeps future refreshes assigning it here.
                router?.confirmAssignment(itemTitle: eventTitle, location: newLocation)
            }

        }

        try? modelContext.save()

    }

}

/// Adds a freeform reminder directly to a place — not sourced from the
/// Reminders app, so refresh leaves it alone (itemKey nil, user-owned).
struct AddReminderSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var location: SavedLocation

    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New reminder for \(location.name)") {
                    TextField("What should Eve remind you here?", text: $text)
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        modelContext.insert(
            LocationReminder(locationID: location.id, text: trimmed, itemKey: nil, isSystemManaged: false)
        )

        try? modelContext.save()

    }

}
