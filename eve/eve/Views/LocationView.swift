import SwiftUI
import SwiftData

struct LocationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SavedLocation.sortOrder) private var savedLocations: [SavedLocation]
    @Query private var locationReminders: [LocationReminder]

    @State private var routingManager: LocationRoutingManager?
    @State private var isSeeding = false

    /// The place whose reminders are currently shown. `nil` falls back to the
    /// first saved place (see `activeLocation`) so Home is selected by default.
    @State private var selectedLocationID: UUID?

    @State private var editingLocation: SavedLocation?
    @State private var addingLocation = false
    @State private var editingReminder: LocationReminder?

    /// The day whose add row was tapped. Presenting on this — rather than a
    /// bare bool — carries which heading the new reminder belongs under.
    @State private var addingReminder: NewReminderTarget?

    /// A day, made identifiable so it can drive `.sheet(item:)`.
    private struct NewReminderTarget: Identifiable {
        let id = UUID()
        var day: Date
    }

    @State private var toast: String?

    /// Which triggers the list is showing. Both on by default — the filter is
    /// for narrowing to one half of a visit, not for hiding things by accident.
    @State private var visibleTriggers: Set<LocationTrigger> = Set(LocationTrigger.allCases)

    var body: some View {
        screen
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Color.eveOnSurface)
        .overlay(alignment: .bottom) {
            if let toast {
                SuccessToast(message: toast)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editingLocation) { location in
            LocationEditSheet(location: location)
        }
        .sheet(isPresented: $addingLocation) {
            AddLocationSheet(nextSortOrder: savedLocations.count)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditSheet(
                reminder: reminder,
                allLocations: savedLocations,
                router: routingManager
            )
        }
        .sheet(item: $addingReminder) { target in
            ReminderEditSheet(
                location: activeLocation,
                defaultDay: target.day,
                allLocations: savedLocations,
                router: routingManager
            )
        }
        .task {
            if routingManager == nil {
                routingManager = LocationRoutingManager(context: modelContext)
            }
            if selectedLocationID == nil {
                selectedLocationID = savedLocations.first?.id
            }
            await seedDefaultsIfNeeded()
        }
        .onChange(of: savedLocations.map(\.id)) { _, ids in
            // Keep the filter pointed at a place that still exists — e.g. after
            // the selected place is deleted, or once seeding creates the first.
            if selectedLocationID == nil || !ids.contains(selectedLocationID!) {
                selectedLocationID = ids.first
            }
        }
    }

    // MARK: - Screen

    private var screen: some View {
        ZStack {
            AuroraBackground()

            if savedLocations.isEmpty {
                emptyLocationsState
            } else {
                VStack(spacing: 0) {
                    locationFilter
                        .padding(.top, Theme.Spacing.xxs)

                    if let location = activeLocation {
                        addressBlock(for: location)
                    }

                    selectedLocationCard
                }
            }
        }
    }

    // MARK: - Location filter

    private var locationFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                // Add a new place — sits to the left of the location chips.
                Button {
                    addingLocation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.eveCardTitle)
                        .frame(width: Theme.Spacing.l, height: Theme.Spacing.l)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.eveOnSurface)
                .accessibilityLabel("Add location")

                ForEach(savedLocations) { location in
                    LocationChip(
                        location: location,
                        isSelected: location.id == activeLocation?.id
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLocationID = location.id
                        }
                    }
                    .contextMenu {
                        Button {
                            editingLocation = location
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            delete(location)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    // MARK: - Address

    /// The selected place's street address, with a shortcut into its editor.
    private func addressBlock(for location: SavedLocation) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {

            VStack(alignment: .leading, spacing: 2) {
                Text("Address:")
                    .font(.eveBody.weight(.semibold))
                    .foregroundStyle(Color.eveOnSurfaceMuted)

                Text(location.address ?? "No address set")
                    .font(.eveDetail)
                    .foregroundStyle(Color.eveOnSurfaceMuted.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                editingLocation = location
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit this place")
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Selected location card

    @ViewBuilder
    private var selectedLocationCard: some View {
        if let location = activeLocation {
            // No location header inside the card — the filter above already
            // shows which place these reminders belong to.
            remindersList(for: location)
                .background(Color.eveSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .shadow(color: Color.eveOnSurface.opacity(0.1), radius: 10, y: 5)
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.gutter)
        }
    }

    private func remindersList(for location: SavedLocation) -> some View {

        let groups = dateGroups(for: location)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {

                filterBar

                if groups.isEmpty {
                    emptyRemindersState(for: location)
                } else {
                    ForEach(groups, id: \.day) { group in
                        dateGroup(group, in: location)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            // Room for the floating + that overlaps the card's lower corner.
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Arriving / Leaving, as toggles rather than a single choice — the two
    /// halves of a visit aren't mutually exclusive, and a picker would force
    /// the user to hide one of them to see the other.
    private var filterBar: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(LocationTrigger.allCases) { trigger in
                    Button {
                        toggle(trigger)
                    } label: {
                        Label(
                            trigger.title,
                            systemImage: visibleTriggers.contains(trigger) ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Filter by arriving or leaving")
        }
    }

    @ViewBuilder
    private func emptyRemindersState(for location: SavedLocation) -> some View {
        if isSeeding && !location.hasBeenSeeded {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.eveOnSurfaceFaint)
                Text("Eve is learning about this place…")
                    .font(.eveBody)
                    .foregroundStyle(Color.eveOnSurfaceFaint)
            }
        } else {
            Text(visibleTriggers.count == LocationTrigger.allCases.count
                 ? "Nothing for this place yet."
                 : "Nothing matches this filter.")
                .font(.eveBody)
                .foregroundStyle(Color.eveOnSurfaceMuted)
        }

        addReminderRow(for: location, on: Calendar.current.startOfDay(for: .now))
    }

    /// One day's worth of reminders: a heading, its rows, the inline add row,
    /// and a rule closing it off.
    private func dateGroup(_ group: DateGroup, in location: SavedLocation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {

            Text(group.day.formatted(.dateTime.day().month(.wide).year()))
                .font(.eveBody.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            ForEach(group.reminders) { reminder in
                LocationReminderRow(
                    reminder: reminder,
                    onToggle: { routingManager?.toggleCompletion(reminder) },
                    onTap: { editingReminder = reminder }
                )
                .contextMenu {
                    Button(role: .destructive) {
                        deleteReminder(reminder)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            addReminderRow(for: location, on: group.day)

            Rectangle()
                .fill(Color.eveOnSurfaceFaint.opacity(0.4))
                .frame(height: 1)
                .padding(.bottom, Theme.Spacing.xs)
        }
    }

    /// Opens the same editor a tap on an existing reminder does, seeded with
    /// the day it was tapped under — the same move as the routine list's add
    /// row, so adding a reminder works identically on both screens.
    private func addReminderRow(for location: SavedLocation, on day: Date) -> some View {
        Button {
            addingReminder = NewReminderTarget(day: day)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Circle()
                    .strokeBorder(
                        Color.eveOnSurfaceFaint.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 3])
                    )
                    .frame(width: 18, height: 18)
                    .frame(width: 22, height: 22)

                Text("Add a reminder…")
                    .font(.eveCardTitle)
                    .foregroundStyle(Color.eveOnSurfaceFaint)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a reminder")
    }

    // MARK: - Empty state

    private var emptyLocationsState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.eveOnSurface.opacity(0.5))
            Text("No places yet")
                .font(.eveSectionTitle)
                .foregroundStyle(Color.eveOnSurface)
            Text("Add a place and Eve will start learning what to remind you there.")
                .font(.eveDetail)
                .foregroundStyle(Color.eveOnSurface.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)

            Button {
                addingLocation = true
            } label: {
                Label("Add Location", systemImage: "plus")
                    .font(.eveButton)
                    // Grows with the label instead of a fixed 200×40 box, so
                    // it doesn't clip at larger Dynamic Type sizes.
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.vertical, Theme.Spacing.s)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.accentColor)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    // MARK: - Data

    /// The place currently shown — the selected one, or the first saved place
    /// as a default so the screen never shows an empty filter when places exist.
    private var activeLocation: SavedLocation? {
        savedLocations.first { $0.id == selectedLocationID } ?? savedLocations.first
    }

    private func reminders(for location: SavedLocation) -> [LocationReminder] {
        locationReminders
            .filter { $0.locationID == location.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// One day's reminders for the selected place, newest day first.
    private struct DateGroup {
        var day: Date
        var reminders: [LocationReminder]
    }

    private func dateGroups(for location: SavedLocation) -> [DateGroup] {

        let calendar = Calendar.current

        let visible = reminders(for: location)
            .filter { visibleTriggers.contains($0.trigger) }

        return Dictionary(grouping: visible) {
            calendar.startOfDay(for: $0.effectiveDate)
        }
        .map { DateGroup(day: $0.key, reminders: $0.value) }
        .sorted { $0.day < $1.day }
    }

    private func toggle(_ trigger: LocationTrigger) {
        // Never let the last one be switched off — an empty filter shows an
        // empty list with no way to tell why.
        if visibleTriggers.contains(trigger) {
            guard visibleTriggers.count > 1 else { return }
            visibleTriggers.remove(trigger)
        } else {
            visibleTriggers.insert(trigger)
        }
    }

    // MARK: - Actions

    /// Seeds Home/Office on first launch, then auto-generates reminders
    /// only for places that have never been seeded before. Re-entering this
    /// screen must NOT re-ask the model for places it already learned —
    /// each call is a fresh, non-deterministic generation, so that would
    /// silently reshuffle wording every time the user opens Locations.
    /// Picking up new calendar activity is what the manual refresh button
    /// (always unconditional — see `refresh()`) is for.
    private func seedDefaultsIfNeeded() async {

        var needsSeed = false

        if savedLocations.isEmpty {
            modelContext.insert(SavedLocation(name: "Home", iconName: "house.fill", isDefault: true, sortOrder: 0))
            modelContext.insert(SavedLocation(name: "Office", iconName: "building.2.fill", isDefault: true, sortOrder: 1))
            try? modelContext.save()
            needsSeed = true
        } else if savedLocations.contains(where: { !$0.hasBeenSeeded }) {
            needsSeed = true
        }

        guard needsSeed else { return }

        await refresh()

    }

    private func refresh() async {
        guard let routingManager else { return }
        isSeeding = true
        await routingManager.seedReminders()
        isSeeding = false
    }

    private func delete(_ location: SavedLocation) {

        for reminder in reminders(for: location) {
            modelContext.delete(reminder)
        }

        let assignments = (try? modelContext.fetch(FetchDescriptor<LocationAssignment>())) ?? []
        for assignment in assignments where assignment.locationID == location.id {
            modelContext.delete(assignment)
        }

        let name = location.name
        modelContext.delete(location)
        try? modelContext.save()

        showToast("\(name) removed")

    }

    private func deleteReminder(_ reminder: LocationReminder) {
        routingManager?.remove(reminder)
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Location chip

private struct LocationChip: View {
    var location: SavedLocation
    var isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: location.iconName)
                .font(.eveCaption)
            Text(location.name)
                .font(.eveCardTitle)
        }
        .foregroundStyle(isSelected ? .white : Color.eveOnSurface)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor : Color.eveSurface.opacity(0.85))
        )
        .overlay(
            Capsule()
                .stroke(Color.eveOnSurface.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Reminder row

private struct LocationReminderRow: View {
    var reminder: LocationReminder
    var onToggle: () -> Void
    var onTap: () -> Void

    /// Reminder text without any legacy "EventTitle: " prefix — the event is
    /// shown on its own subtitle line now.
    private var title: String {
        guard let event = reminder.eventTitle else { return reminder.text }
        let prefix = "\(event): "
        return reminder.text.hasPrefix(prefix)
            ? String(reminder.text.dropFirst(prefix.count))
            : reminder.text
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? Color.accentColor : Color.eveOnSurfaceFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.eveCardTitle)
                    .foregroundStyle(reminder.isCompleted ? Color.eveOnSurfaceFaint : Color.eveOnSurface)
                    .strikethrough(reminder.isCompleted, color: .eveOnSurfaceFaint)
                    .multilineTextAlignment(.leading)

                if let event = reminder.eventTitle, !event.isEmpty {
                    Text(event)
                        .font(.eveCaption)
                        .foregroundStyle(Color.eveOnSurfaceFaint)
                        .lineLimit(1)
                }

                TriggerTag(trigger: reminder.trigger)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Says which half of the visit a reminder belongs to. Small and quiet — it
/// labels the row rather than competing with its text.
private struct TriggerTag: View {
    var trigger: LocationTrigger

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: trigger.symbol)
            Text(trigger.title)
        }
        .font(.eveOverline)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
    .modelContainer(for: SavedLocation.self, inMemory: true)
}
