import SwiftUI
import SwiftData

struct LocationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SavedLocation.sortOrder) private var savedLocations: [SavedLocation]
    @Query private var locationReminders: [LocationReminder]

    @State private var routingManager: LocationRoutingManager?
    @State private var isSeeding = false

    @State private var editingLocation: SavedLocation?
    @State private var addingLocation = false
    @State private var editingReminder: LocationReminder?
    @State private var addingReminderTo: SavedLocation?

    @State private var toast: String?

    var body: some View {
        ZStack {
            Color(hex: "#4F83AB").ignoresSafeArea()

            GeometryReader { proxy in
                Ellipse()
                    .fill(Color(hex: "#E0ECF7"))
                    .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
                    .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                    }

                    Spacer()

                    Text("Locations")
                        .font(.system(size: 34, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#1D3557"))

                    Spacer()

                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                    }
                    .disabled(isSeeding)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)

                if savedLocations.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#1D3557").opacity(0.5))
                        Text("No places yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                        Text("Add a place and Eve will start learning what to remind you there.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#1D3557").opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button {
                            addingLocation = true
                        } label: {
                            Label("Add Location", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "#E0ECF7"))
                                .frame(width: 200, height: 40)
                                .background(Color(hex: "#368BC8"))
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    Spacer()
                } else {
                    // A native List is required here (not ScrollView/VStack) so
                    // `.swipeActions` gives the real Apple swipe-to-delete gesture.
                    List {
                        ForEach(savedLocations) { location in
                            LocationCardView(
                                location: location,
                                reminders: reminders(for: location),
                                isSeeding: isSeeding && !location.hasBeenSeeded,
                                onTapReminder: { reminder in editingReminder = reminder },
                                onAddReminder: { addingReminderTo = location }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(location)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingLocation = location
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }

                        Button {
                            addingLocation = true
                        } label: {
                            Label("Add Location", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "#E0ECF7"))
                                .frame(width: 200, height: 40)
                                .background(Color(hex: "#368BC8"))
                                .cornerRadius(20)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, 8)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .listRowSpacing(20)
                    .contentMargins(.horizontal, 24, for: .scrollContent)
                    .contentMargins(.bottom, 40, for: .scrollContent)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) {
            if let toast {
                SuccessToast(message: toast)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editingLocation) { location in
            LocationEditSheet(location: location)
        }
        .sheet(isPresented: $addingLocation) {
            LocationEditSheet(location: nil, nextSortOrder: savedLocations.count)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditSheet(
                reminder: reminder,
                allLocations: savedLocations,
                onMoved: { itemTitle, newLocation in
                    routingManager?.confirmAssignment(itemTitle: itemTitle, location: newLocation)
                }
            )
        }
        .sheet(item: $addingReminderTo) { location in
            AddReminderSheet(location: location)
        }
        .task {
            if routingManager == nil {
                routingManager = LocationRoutingManager(context: modelContext)
            }
            await seedDefaultsIfNeeded()
        }
    }

    // MARK: - Data

    private func reminders(for location: SavedLocation) -> [LocationReminder] {
        locationReminders
            .filter { $0.locationID == location.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Actions

    private func seedDefaultsIfNeeded() async {

        if savedLocations.isEmpty {
            modelContext.insert(SavedLocation(name: "Home", iconName: "house.fill", isDefault: true, sortOrder: 0))
            modelContext.insert(SavedLocation(name: "Office", iconName: "building.2.fill", isDefault: true, sortOrder: 1))
            try? modelContext.save()
        }

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

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

struct LocationCardView: View {
    var location: SavedLocation
    var reminders: [LocationReminder]
    var isSeeding: Bool
    var onTapReminder: (LocationReminder) -> Void
    var onAddReminder: () -> Void

    private var subtitle: String {
        if isSeeding && reminders.isEmpty {
            return "Eve is learning about this place…"
        }
        return reminders.isEmpty
            ? "No reminders yet"
            : "Eve has learned \(reminders.count) reminder\(reminders.count == 1 ? "" : "s")"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color(hex: "#E8F3FF")

            // Large background icon
            VStack {
                Image(systemName: location.iconName)
                    .font(.system(size: 110))
                    .foregroundColor(Color(hex: "#C4D7EA"))
                    .offset(x: -30, y: 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(location.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#1D3557"))

                    if let address = location.address, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#94A8BC"))
                            .padding(.leading, 4)
                            .padding(.top, 4)
                            .lineLimit(1)
                    } else {
                        Text("No address yet")
                            .font(.system(size: 11, weight: .semibold))
                            .italic()
                            .foregroundColor(Color(hex: "#94A8BC").opacity(0.7))
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }

                    Spacer()
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#94A8BC"))
                    .padding(.bottom, 8)

                ForEach(reminders) { reminder in
                    Button {
                        onTapReminder(reminder)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: "#4A60B2"))
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle().stroke(Color(hex: "#94A8BC").opacity(0.5), lineWidth: 1)
                                )
                            Text(reminder.text)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onAddReminder()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#368BC8"))
                        Text("Add reminder")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#368BC8"))
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .cornerRadius(24)
        .shadow(color: Color(hex: "#1D3557").opacity(0.1), radius: 10, y: 5)
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
    .modelContainer(for: SavedLocation.self, inMemory: true)
}
