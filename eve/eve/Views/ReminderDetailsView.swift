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

    /// A place a new reminder starts pinned to — set when the Location tab's
    /// add row opens this, so the sheet arrives with Places already on.
    var defaultPlace: SavedLocation?

    @Query(sort: \SavedLocation.sortOrder) private var places: [SavedLocation]
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]

    // Edited in local state and written back on save, so backing out with ✕
    // leaves the stored reminder untouched.
    @State private var title = ""
    @State private var notes = ""
    @State private var url = ""
    @State private var date = Date.now
    @State private var hasTime = true
    @State private var repeatRule: RepeatRule = .never
    @State private var attachedOccurrenceID: String?

    /// The Places switch. On with nothing picked yet is a valid state — it's
    /// what shows the "Search or Enter Address" row.
    @State private var hasLocation = false
    @State private var place: ReminderPlace?
    @State private var locationTrigger: LocationTrigger = .arriving

    /// Pushes the Location screen.
    @State private var isPickingPlace = false

    @State private var isShowingDatePicker = false
    @State private var isShowingTimePicker = false

    @State private var isConfirmingDiscard = false

    /// What the form held when it opened. Anything different is unsaved work.
    @State private var original: Draft?

    /// Every editable value, so "has anything changed?" is one comparison
    /// rather than nine that can fall out of step as fields are added.
    private struct Draft: Equatable {
        var title: String
        var notes: String
        var url: String
        var date: Date
        var hasTime: Bool
        var repeatRule: RepeatRule
        var attachedOccurrenceID: String?
        var hasLocation: Bool
        var place: ReminderPlace?
        var locationTrigger: LocationTrigger
    }

    private var draft: Draft {
        Draft(
            title: title,
            notes: notes,
            url: url,
            date: date,
            hasTime: hasTime,
            repeatRule: repeatRule,
            attachedOccurrenceID: attachedOccurrenceID,
            hasLocation: hasLocation,
            place: place,
            locationTrigger: locationTrigger
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

    /// The day's events — the candidates for "attach event".
    private var attachableEvents: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }

    private var attachedEvent: CalendarEvent? {
        attachableEvents.first { $0.occurrenceID == attachedOccurrenceID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                Form {
                    textSection
                    dateAndTimeSection
                    eventSection
                    placesSection
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
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .navigationDestination(isPresented: $isPickingPlace) {
                ReminderLocationPicker(place: $place, trigger: $locationTrigger)
            }
            .onAppear(perform: load)
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

    /// Title and notes share a cell, the way Reminders does it: the notes
    /// are a continuation of the title, not a separate field to find.
    private var textSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TextField("Title", text: $title)
                    .font(.title3)

                TextField("Notes", text: $notes, axis: .vertical)
                    .font(.eveBody)
                    .lineLimit(1...4)
            }
            .padding(.vertical, Theme.Spacing.xxs)

            TextField("URL", text: $url)
                .font(.eveBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .listRowBackground(Color.eveSurface)
    }

    private var dateAndTimeSection: some View {
        Section {

            // No Date switch: every reminder has a day. Home is "Today", and
            // the calendar timeline is per-day, so an undated reminder would
            // have nowhere to be listed. Tap to change it.
            Button {
                withAnimation { isShowingDatePicker.toggle() }
            } label: {
                iconRow(
                    "calendar",
                    label: "Date",
                    value: dateLabel,
                    tint: isShowingDatePicker ? Color.accentColor : Color.eveOnSurfaceMuted
                )
            }
            .buttonStyle(.plain)

            if isShowingDatePicker {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }

            // The switch is the toggle; the label is the disclosure. Two
            // controls in one row, so each gets its own hit area rather than
            // the row deciding for them.
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    guard hasTime else { return }
                    withAnimation { isShowingTimePicker.toggle() }
                } label: {
                    iconRow(
                        "clock",
                        label: "Time",
                        value: hasTime ? date.formatted(date: .omitted, time: .shortened) : nil,
                        tint: Color.accentColor
                    )
                }
                .buttonStyle(.plain)

                Toggle("Time", isOn: $hasTime.animation())
                    .labelsHidden()
            }

            if hasTime && isShowingTimePicker {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: Theme.Spacing.s) {
                iconRow("repeat", label: "Repeat", value: nil, tint: .clear)

                Picker("Repeat", selection: $repeatRule) {
                    ForEach(RepeatRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.eveOnSurfaceMuted)
            }
        } header: {
            sectionHeader("Date & Time")
        }
        .listRowBackground(Color.eveSurface)
        // Switching time on opens the wheel — that's what the switch is for.
        // Off folds it away so the row doesn't keep a picker for nothing.
        .onChange(of: hasTime) { _, isOn in
            withAnimation { isShowingTimePicker = isOn }
        }
    }

    private var eventSection: some View {
        Section {
            Menu {
                Picker("Attach Event", selection: $attachedOccurrenceID) {
                    Text("None").tag(String?.none)
                    ForEach(attachableEvents, id: \.occurrenceID) { event in
                        Text(event.title).tag(String?.some(event.occurrenceID))
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                        .frame(width: 22)

                    Text(eventLabel)
                        .font(.eveBody)
                        .foregroundStyle(attachedEvent == nil ? Color.eveOnSurfaceMuted : Color.eveOnSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.eveDetail.weight(.semibold))
                        .foregroundStyle(Color.eveOnSurfaceFaint)
                }
                .contentShape(Rectangle())
            }
            .disabled(attachableEvents.isEmpty)
        } header: {
            sectionHeader("Attached Event")
        }
        .listRowBackground(Color.eveSurface)
    }

    private var eventLabel: String {
        if let attachedEvent { return attachedEvent.title }
        return attachableEvents.isEmpty ? "No events on this day" : "None"
    }

    private var placesSection: some View {
        Section {
            Toggle(isOn: $hasLocation.animation()) {
                iconRow("location", label: "Location", value: nil, tint: .clear)
            }

            if hasLocation {
                if let place {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.eveOnSurfaceMuted)
                            .frame(width: 22)
                            .padding(.top, 2)

                        // The name is the way back into the picker, so a
                        // wrong pick is one tap from being fixed.
                        Button {
                            isPickingPlace = true
                        } label: {
                            Text(place.name)
                                .font(.eveBody)
                                .foregroundStyle(Color.eveOnSurface)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Picker("Remind me when", selection: $locationTrigger) {
                            ForEach(LocationTrigger.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Color.eveOnSurfaceMuted)
                    }
                } else {
                    Button {
                        isPickingPlace = true
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color.eveOnSurfaceMuted)
                                .frame(width: 22)
                            Text("Search or Enter Address")
                                .font(.eveBody)
                                .foregroundStyle(Color.eveOnSurfaceFaint)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader("Places")
        }
        .listRowBackground(Color.eveSurface)
        // Off means off: the pick goes with it, so the saved reminder can't
        // quietly keep a place the user switched away from.
        .onChange(of: hasLocation) { _, isOn in
            if !isOn { place = nil }
        }
    }

    // MARK: - Row pieces

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.eveCardTitle)
            .foregroundStyle(Color.eveOnSurfaceMuted)
            .textCase(nil)
    }

    /// Icon, label, and an optional value underneath — the shape every row
    /// in the Date & Time and Places cards shares.
    private func iconRow(_ icon: String, label: String, value: String?, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(Color.eveOnSurfaceMuted)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.eveBody)
                    .foregroundStyle(Color.eveOnSurface)
                if let value {
                    Text(value)
                        .font(.eveDetail)
                        .foregroundStyle(tint)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Load / save

    private func load() {
        // Snapshotting on the way out of this function, so both paths record
        // exactly what the user was shown.
        defer { original = draft }

        guard let reminder else {
            // Callers that only know the day — the Location tab's date
            // headings, the calendar's selected day — hand over midnight.
            // A reminder at 0.00 is never what was meant, so take the time
            // of day from the clock instead.
            let calendar = Calendar.current
            if defaultDate == calendar.startOfDay(for: defaultDate) {
                let now = calendar.dateComponents([.hour, .minute], from: .now)
                date = calendar.date(
                    bySettingHour: now.hour ?? 9, minute: now.minute ?? 0, second: 0, of: defaultDate
                ) ?? defaultDate
            } else {
                date = defaultDate
            }
            if let defaultPlace {
                hasLocation = true
                place = ReminderPlace(
                    savedID: defaultPlace.id,
                    name: defaultPlace.name,
                    address: defaultPlace.address,
                    latitude: defaultPlace.latitude,
                    longitude: defaultPlace.longitude
                )
            }
            return
        }
        title = reminder.text
        notes = reminder.notes ?? ""
        url = reminder.url ?? ""
        date = reminder.reminderDate
        hasTime = reminder.hasTime
        repeatRule = reminder.repeatRule
        attachedOccurrenceID = reminder.occurrenceID.hasPrefix("manual-")
            ? nil
            : reminder.occurrenceID
        locationTrigger = reminder.locationTrigger

        if let saved = places.first(where: { $0.id == reminder.locationID }) {
            hasLocation = true
            place = ReminderPlace(
                savedID: saved.id,
                name: saved.name,
                address: saved.address,
                latitude: saved.latitude,
                longitude: saved.longitude
            )
        }
    }

    /// The `SavedLocation` a pick stands for: the one it came from, one
    /// already saved at the same spot, or a new row. Picking the office
    /// twice shouldn't give the Location tab two offices.
    private func savedLocation(for place: ReminderPlace) -> SavedLocation {

        if let existing = places.first(where: { $0.id == place.savedID }) {
            return existing
        }

        // ~30 m — close enough to be the same building, far enough that two
        // shops on one street stay distinct.
        let tolerance = 0.0003
        if let latitude = place.latitude, let longitude = place.longitude,
           let nearby = places.first(where: {
               guard let lat = $0.latitude, let lon = $0.longitude else { return false }
               return abs(lat - latitude) < tolerance && abs(lon - longitude) < tolerance
           }) {
            return nearby
        }

        let saved = SavedLocation(
            name: place.name,
            address: place.address,
            iconName: LocationIconResolver.icon(for: place.category) ?? LocationIconResolver.defaultIcon,
            latitude: place.latitude,
            longitude: place.longitude,
            sortOrder: places.count
        )
        modelContext.insert(saved)
        return saved
    }

    private func save() {

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = attachedEvent

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
        target.repeatRule = repeatRule
        target.locationTrigger = locationTrigger
        target.locationID = (hasLocation ? place : nil).map { savedLocation(for: $0).id }

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
