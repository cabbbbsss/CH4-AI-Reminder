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

    /// Backing state for the inline "type a new reminder" row at the bottom of
    /// the list. Focus is driven from here so the bottom-right + can jump to it.
    @State private var newReminderText = ""
    @FocusState private var newReminderFocused: Bool

    @State private var toast: String?

    var body: some View {
        screen
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Color(.textPrimary))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isSeeding)
            }
        }
        .overlay {
            // While typing a new reminder, a tap anywhere cancels it — clears
            // the field and dismisses the keyboard. Only hit-testable while
            // focused, so it never interferes with normal list interaction.
            if newReminderFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { cancelNewReminder() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !savedLocations.isEmpty {
                addReminderButton
            }
        }
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
            Color(.bgPrimary).ignoresSafeArea()

            GeometryReader { proxy in
                Ellipse()
                    .fill(Color(.bgSecondary))
                    .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
                    .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
            }
            .ignoresSafeArea()

            if savedLocations.isEmpty {
                emptyLocationsState
            } else {
                VStack(spacing: 0) {
                    locationFilter
                        .padding(.top, 4)
                    selectedLocationCard
                }
            }
        }
    }

    // MARK: - Location filter

    private var locationFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Add a new place — sits to the left of the location chips.
                Button {
                    addingLocation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(.textPrimary))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.bgSecondary).opacity(0.85)))
                        .overlay(Circle().stroke(Color(.textPrimary).opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)

                ForEach(savedLocations) { location in
                    LocationChip(
                        location: location,
                        isSelected: location.id == activeLocation?.id
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLocationID = location.id
                        }
                        // Fresh place → clear whatever was half-typed elsewhere.
                        newReminderText = ""
                        newReminderFocused = false
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
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Selected location card

    @ViewBuilder
    private var selectedLocationCard: some View {
        if let location = activeLocation {
            // No location header inside the card — the filter above already
            // shows which place these reminders belong to.
            remindersList(for: location)
                .background(Color(.bgSecondary))
                .cornerRadius(24)
                .shadow(color: Color(.textPrimary).opacity(0.1), radius: 10, y: 5)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }

    private func remindersList(for location: SavedLocation) -> some View {
        let items = reminders(for: location)

        return List {
            if items.isEmpty && isSeeding && !location.hasBeenSeeded {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Color(.textQuarternary))
                    Text("Eve is learning about this place…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(.textQuarternary))
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(items) { reminder in
                ReminderRow(
                    reminder: reminder,
                    onToggle: { routingManager?.toggleCompletion(reminder) },
                    onTap: { editingReminder = reminder }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparatorTint(Color(.bgTertiary))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Icon-only, red — no "Delete" text.
                    Button(role: .destructive) {
                        deleteReminder(reminder)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }

            // Inline new-reminder row — type and press return to add, exactly
            // like the Reminders app. No separate "add" button.
            HStack(spacing: 12) {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundColor(Color(.textQuarternary).opacity(0.5))

                TextField("Add Reminder", text: $newReminderText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.textPrimary))
                    .focused($newReminderFocused)
                    .submitLabel(.next)
                    .onSubmit { commitNewReminder(to: location) }

                Spacer(minLength: 0)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        // Extra bottom room so the last (inline) row isn't hidden behind the
        // floating + button that overlaps the card's lower-right corner.
        .contentMargins(.bottom, 52, for: .scrollContent)
    }

    // MARK: - Bottom-right add-reminder button

    private var addReminderButton: some View {
        Button {
            newReminderFocused = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: Color(.textPrimary).opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        // Equal inset from the screen's bottom and trailing edges, matching the
        // card's 24pt horizontal padding so the button sits at its corner.
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Empty state

    private var emptyLocationsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 44))
                .foregroundColor(Color(.textPrimary).opacity(0.5))
            Text("No places yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(.textPrimary))
            Text("Add a place and Eve will start learning what to remind you there.")
                .font(.system(size: 13))
                .foregroundColor(Color(.textPrimary).opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                addingLocation = true
            } label: {
                Label("Add Location", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.textSecondary))
                    .frame(width: 200, height: 40)
                    .background(Color.accentColor)
                    .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
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

    // MARK: - Actions

    /// Adds the inline-typed reminder to the active place, then keeps focus so
    /// the user can keep adding rows back-to-back — like the Reminders app.
    private func commitNewReminder(to location: SavedLocation) {

        let trimmed = newReminderText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            newReminderFocused = false
            return
        }

        modelContext.insert(
            LocationReminder(locationID: location.id, text: trimmed, itemKey: nil, isSystemManaged: false)
        )
        try? modelContext.save()

        newReminderText = ""
        newReminderFocused = true

    }

    /// Abandons an in-progress inline reminder — clears the field and drops
    /// focus (dismissing the keyboard). Triggered by tapping anywhere while
    /// the new-reminder field is focused.
    private func cancelNewReminder() {
        newReminderText = ""
        newReminderFocused = false
    }

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
        HStack(spacing: 7) {
            Image(systemName: location.iconName)
                .font(.system(size: 13, weight: .semibold))
            Text(location.name)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(isSelected ? .white : Color(.textPrimary))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor : Color(.bgSecondary).opacity(0.85))
        )
        .overlay(
            Capsule()
                .stroke(Color(.textPrimary).opacity(isSelected ? 0 : 0.08), lineWidth: 1)
        )
    }
}

// MARK: - Reminder row (Apple Reminders style)

private struct ReminderRow: View {
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
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(reminder.isCompleted ? Color.accentColor : Color(.textQuarternary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(reminder.isCompleted ? Color(.textQuarternary) : Color(.textPrimary))
                    .strikethrough(reminder.isCompleted, color: Color(.textQuarternary))
                    .multilineTextAlignment(.leading)

                // Subtitle = related calendar/reminder event. Empty for
                // freeform reminders not tied to any event.
                if let event = reminder.eventTitle, !event.isEmpty {
                    Text(event)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.textQuarternary))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
    .modelContainer(for: SavedLocation.self, inMemory: true)
}
