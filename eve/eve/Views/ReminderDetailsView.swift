//
//  ReminderDetailsView.swift
//  Eve
//
//  The full editor behind a routine row's ⓘ button, and the sheet the dashed
//  "add" row opens. Home shows only title, notes and time; everything else
//  about a reminder is set here.
//

import SwiftUI
import SwiftData

struct ReminderDetailsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The reminder being edited, or nil when this is a new one.
    var reminder: CalendarReminder?

    /// The day a new reminder lands on.
    var defaultDate: Date = .now

    @Query(sort: \SavedLocation.sortOrder) private var places: [SavedLocation]
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]

    // Edited in local state and written back on save, so backing out with ✕
    // leaves the stored reminder untouched.
    @State private var title = ""
    @State private var notes = ""
    @State private var url = ""
    @State private var date = Date.now
    @State private var hasTime = true
    @State private var locationID: UUID?
    @State private var locationTrigger: LocationTrigger = .arriving

    /// Presents the map picker, which creates a geotagged `SavedLocation`.
    @State private var isPickingOnMap = false
    @State private var attachedOccurrenceID: String?
    @State private var repeatRule: RepeatRule = .never
    @State private var earlyReminder: EarlyReminder = .none

    @State private var isShowingDatePicker = false
    @State private var isShowingTimePicker = false

    @State private var isConfirmingDiscard = false

    /// What the form held when it opened. Anything different is unsaved work.
    @State private var original: Draft?

    private var isNew: Bool { reminder == nil }

    /// Every editable value, so "has anything changed?" is one comparison
    /// rather than nine that can fall out of step as fields are added.
    private struct Draft: Equatable {
        var title: String
        var notes: String
        var url: String
        var date: Date
        var hasTime: Bool
        var locationID: UUID?
        var locationTrigger: LocationTrigger
        var attachedOccurrenceID: String?
        var repeatRule: RepeatRule
        var earlyReminder: EarlyReminder
    }

    private var draft: Draft {
        Draft(
            title: title,
            notes: notes,
            url: url,
            date: date,
            hasTime: hasTime,
            locationID: locationID,
            locationTrigger: locationTrigger,
            attachedOccurrenceID: attachedOccurrenceID,
            repeatRule: repeatRule,
            earlyReminder: earlyReminder
        )
    }

    /// Nil `original` means the form hasn't loaded yet, so nothing can have
    /// changed — without that guard the sheet would guard itself on appear.
    private var hasChanges: Bool {
        guard let original else { return false }
        return draft != original
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Today's events, newest first — the candidates for "attach event".
    private var attachableEvents: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                Form {
                    textSection
                    dateAndTimeSection
                    placesSection
                    eventSection
                    repeatSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        // Nothing to lose, nothing to ask about.
                        if hasChanges {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Discard")
                    // Anchored to the ✕ it came from, so it reads as a
                    // consequence of that tap.
                    .confirmationDialog(
                        "Are you sure you want to discard changes?",
                        isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) { }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $isPickingOnMap) {
                AddLocationSheet(nextSortOrder: places.count)
            }
            // The picker saves its own `SavedLocation` and dismisses, so the
            // new place arrives here as a change to the query rather than as a
            // return value. Selecting the newest one is what the user meant by
            // choosing it.
            .onChange(of: places.count) { previous, current in
                guard current > previous else { return }
                locationID = places.max(by: { $0.createdAt < $1.createdAt })?.id
            }
            // Blocks the swipe while there is unsaved work. On its own this
            // just refuses silently, so the reporter below turns the refusal
            // into the same question the ✕ asks.
            .interactiveDismissDisabled(hasChanges)
            .background(
                SheetDismissAttemptReporter(isGuarded: hasChanges) {
                    isConfirmingDiscard = true
                }
            )
        }
    }

    // MARK: - Sections

    private var textSection: some View {
        Section {
            TextField("Title", text: $title)
                .font(.eveBody)

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...4)

            TextField("URL", text: $url)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    private var dateAndTimeSection: some View {
        Section("Date & Time") {

            // No Date toggle: every reminder has a day. Home is "Today", and
            // the calendar timeline is per-day, so an undated reminder would
            // have nowhere to be listed.
            Button {
                withAnimation { isShowingDatePicker.toggle() }
            } label: {
                detailRow(
                    icon: "calendar",
                    label: "Date",
                    value: date.formatted(date: .abbreviated, time: .omitted)
                )
            }
            .buttonStyle(.plain)

            if isShowingDatePicker {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }

            Toggle(isOn: $hasTime.animation()) {
                detailRow(
                    icon: "clock",
                    label: "Time",
                    value: hasTime
                        ? date.formatted(date: .omitted, time: .shortened)
                        : "All day"
                )
            }

            if hasTime {
                Button {
                    withAnimation { isShowingTimePicker.toggle() }
                } label: {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.eveCardTitle)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if isShowingTimePicker {
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
            }

            Picker(selection: $earlyReminder) {
                ForEach(EarlyReminder.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Label("Early Reminder", systemImage: "bell.badge")
            }
        }
    }

    private var placesSection: some View {
        Section("Places") {
            Picker(selection: $locationID) {
                Text("None").tag(UUID?.none)
                ForEach(places) { place in
                    Text(place.name).tag(UUID?.some(place.id))
                }
            } label: {
                Label("Location", systemImage: "location")
            }

            // Drops straight into the map picker, which geotags a new place
            // and saves it — so the list above is somewhere to pick from
            // rather than the only way in.
            Button {
                isPickingOnMap = true
            } label: {
                Label("Choose on Map", systemImage: "mappin.and.ellipse")
            }

            if let place = selectedPlace {

                if let address = place.address {
                    Text(address)
                        .font(.eveDetail)
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                }

                Picker("Remind me when", selection: $locationTrigger) {
                    ForEach(LocationTrigger.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                // Says plainly what changes, because a place swaps the trigger
                // rather than adding one.
                Text("Delivered when you're \(locationTrigger.title.lowercased()) \(place.name), instead of at the time above.")
                    .font(.eveDetail)
                    .foregroundStyle(Color.eveOnSurfaceMuted)
            }
        }
    }

    private var selectedPlace: SavedLocation? {
        places.first { $0.id == locationID }
    }

    private var eventSection: some View {
        Section("Event") {
            Picker(selection: $attachedOccurrenceID) {
                Text("None").tag(String?.none)
                ForEach(attachableEvents, id: \.occurrenceID) { event in
                    Text(event.title).tag(String?.some(event.occurrenceID))
                }
            } label: {
                Label("Attach Event", systemImage: "calendar.badge.plus")
            }
            .disabled(attachableEvents.isEmpty)

            if attachableEvents.isEmpty {
                Text("No events on your calendar for this day.")
                    .font(.eveDetail)
                    .foregroundStyle(Color.eveOnSurfaceMuted)
            }
        }
    }

    private var repeatSection: some View {
        Section("Repeat") {
            Picker(selection: $repeatRule) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.title).tag(rule)
                }
            } label: {
                Label("Repeat", systemImage: "repeat")
            }

            if repeatRule != .never {
                Text("The next one is created when you tick this off.")
                    .font(.eveDetail)
                    .foregroundStyle(Color.eveOnSurfaceMuted)
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(Color.eveOnSurfaceMuted)
        }
    }

    // MARK: - Load / save

    private func load() {
        // Snapshotting on the way out of this function, so both paths record
        // exactly what the user was shown.
        defer { original = draft }

        guard let reminder else {
            date = defaultDate
            return
        }
        title = reminder.text
        notes = reminder.notes ?? ""
        url = reminder.url ?? ""
        date = reminder.reminderDate
        hasTime = reminder.hasTime
        locationID = reminder.locationID
        locationTrigger = reminder.locationTrigger
        attachedOccurrenceID = reminder.occurrenceID.hasPrefix("manual-")
            ? nil
            : reminder.occurrenceID
        repeatRule = reminder.repeatRule
        earlyReminder = reminder.earlyReminder
    }

    private func save() {

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = attachableEvents.first { $0.occurrenceID == attachedOccurrenceID }

        // An all-day reminder still needs a moment to sort by; 9am reads as
        // "sometime today" without claiming a specific time.
        let effectiveDate = hasTime
            ? date
            : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date

        let target: CalendarReminder

        if let reminder {
            target = reminder
        } else {
            target = CalendarReminder(
                occurrenceID: attached?.occurrenceID ?? "manual-\(UUID().uuidString)",
                eventTitle: attached?.title ?? "",
                eventDate: attached?.startDate ?? effectiveDate,
                text: trimmedTitle,
                isSystemManaged: false
            )
            modelContext.insert(target)
        }

        target.text = trimmedTitle
        target.notes = notes.isEmpty ? nil : notes
        target.url = url.isEmpty ? nil : url
        target.scheduledDate = effectiveDate
        target.hasTime = hasTime
        target.locationID = locationID
        target.locationTrigger = locationTrigger
        target.repeatRule = repeatRule
        target.earlyReminder = earlyReminder

        if let attached {
            target.occurrenceID = attached.occurrenceID
            target.eventTitle = attached.title
            target.eventDate = attached.startDate
        } else if !target.occurrenceID.hasPrefix("manual-") {
            // Detached from its event: keep the row, drop the link.
            target.occurrenceID = "manual-\(UUID().uuidString)"
            target.eventTitle = ""
        }

        // Any edit makes the row the user's — a reload must not regenerate it.
        target.isSystemManaged = false

        try? modelContext.save()

        // The pending notification is now stale in every case: the time, the
        // lead-in or the trigger may all have moved.
        let scheduler = ReminderScheduler(context: modelContext)
        Task { await scheduler.sync(target) }
    }
}

#Preview {
    ReminderDetailsView()
        .modelContainer(for: CalendarReminder.self, inMemory: true)
}
