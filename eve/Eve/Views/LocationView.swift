import SwiftUI
import SwiftData
import CoreLocation

/// One place to show on the Locations screen, from any real source.
private struct PlaceEntry: Identifiable {
    enum Source { case current, visited, calendar, reminder }

    let id: String          // unique key (source + name)
    let name: String
    let icon: String
    let subtitle: String
    let address: String?
    let chips: [String]
    let extraCount: Int
    let source: Source
}

struct LocationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    // Real visit log (LocationActivityManager → HistoryItem .locationVisited).
    @Query(sort: \HistoryItem.timestamp, order: .reverse)
    private var history: [HistoryItem]

    // Real calendar & reminder mirrors — some carry a location.
    @Query private var events: [CalendarEvent]
    @Query private var reminders: [ReminderItem]

    @State private var currentPlace: String?
    @State private var toast: String?

    private let locationService = LocationService()

    /// LocationActivityManager writes visits as "Arrived near <place>".
    private static let arrivalPrefix = "Arrived near "

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
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)

                let entries = places

                if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#1D3557").opacity(0.5))
                        Text("No places yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                        Text("Locations you visit, and places from your calendar and reminders, will appear here.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#1D3557").opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    // A native List is required here (not ScrollView/VStack) so
                    // `.swipeActions` gives the real Apple swipe-to-delete gesture.
                    List {
                        ForEach(entries) { entry in
                            LocationCardView(
                                iconName: entry.icon,
                                title: entry.name,
                                subtitle: entry.subtitle,
                                address: entry.address,
                                recentlyEdited: entry.source == .current,
                                reminders: entry.chips,
                                extraCount: entry.extraCount
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // Only visit history is ours to delete; calendar,
                                // reminder and current-location entries are live.
                                if entry.source == .visited {
                                    Button(role: .destructive) {
                                        deleteVisited(named: entry.name)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
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
        .task {
            await loadCurrentPlace()
        }
    }

    // MARK: - Building the curated list

    /// Merges every real source into one deduplicated list, in priority
    /// order: current location → visited places → calendar → reminders.
    private var places: [PlaceEntry] {

        var result: [PlaceEntry] = []
        var seen = Set<String>()

        func addUnique(_ entry: PlaceEntry) {
            let key = entry.name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            result.append(entry)
        }

        // 1. Current location (baseline — always shown when available).
        if let currentPlace {
            addUnique(
                PlaceEntry(
                    id: "current",
                    name: currentPlace,
                    icon: "location.circle.fill",
                    subtitle: "You're here now",
                    address: nil,
                    chips: [],
                    extraCount: 0,
                    source: .current
                )
            )
        }

        // 2. Visited places, aggregated from history.
        for place in visitedPlaces {
            addUnique(
                PlaceEntry(
                    id: "visited-\(place.name)",
                    name: place.name,
                    icon: "mappin.and.ellipse",
                    subtitle: "Visited \(place.visits.count) time\(place.visits.count == 1 ? "" : "s")",
                    address: "Last seen \(place.visits.first!.formatted(date: .abbreviated, time: .shortened))",
                    chips: place.visits.prefix(3).map { $0.formatted(date: .abbreviated, time: .shortened) },
                    extraCount: max(0, place.visits.count - 3),
                    source: .visited
                )
            )
        }

        // 3. Places mentioned in the calendar.
        for (name, titles) in locationsFromCalendar {
            addUnique(
                PlaceEntry(
                    id: "calendar-\(name)",
                    name: name,
                    icon: "calendar",
                    subtitle: "From your calendar",
                    address: nil,
                    chips: Array(titles.prefix(3)),
                    extraCount: max(0, titles.count - 3),
                    source: .calendar
                )
            )
        }

        // 4. Places attached to reminders.
        for (name, titles) in locationsFromReminders {
            addUnique(
                PlaceEntry(
                    id: "reminder-\(name)",
                    name: name,
                    icon: "checklist",
                    subtitle: "From a reminder",
                    address: nil,
                    chips: Array(titles.prefix(3)),
                    extraCount: max(0, titles.count - 3),
                    source: .reminder
                )
            )
        }

        return result
    }

    private struct VisitedPlace {
        let name: String
        let visits: [Date]   // newest first
    }

    private var visitedPlaces: [VisitedPlace] {
        var byName: [String: [Date]] = [:]
        for item in history where item.type == .locationVisited {
            byName[placeName(from: item.title), default: []].append(item.timestamp)
        }
        return byName
            .map { VisitedPlace(name: $0.key, visits: $0.value.sorted(by: >)) }
            .sorted {
                $0.visits.count != $1.visits.count
                    ? $0.visits.count > $1.visits.count
                    : ($0.visits.first ?? .distantPast) > ($1.visits.first ?? .distantPast)
            }
    }

    /// Distinct calendar locations → the event titles held there.
    private var locationsFromCalendar: [(String, [String])] {
        grouped(events.compactMap { event in
            event.location.map { ($0, event.title) }
        })
    }

    /// Distinct reminder locations → the reminder titles held there.
    private var locationsFromReminders: [(String, [String])] {
        grouped(reminders.compactMap { reminder in
            reminder.location.map { ($0, reminder.title) }
        })
    }

    /// Groups (place, item) pairs into (place, [items]), dropping blanks,
    /// preserving first-seen order of places.
    private func grouped(_ pairs: [(String, String)]) -> [(String, [String])] {
        var order: [String] = []
        var byPlace: [String: [String]] = [:]
        for (placeRaw, item) in pairs {
            let place = placeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !place.isEmpty else { continue }
            if byPlace[place] == nil { order.append(place) }
            byPlace[place, default: []].append(item)
        }
        return order.map { ($0, byPlace[$0] ?? []) }
    }

    private func placeName(from title: String) -> String {
        title.hasPrefix(Self.arrivalPrefix)
            ? String(title.dropFirst(Self.arrivalPrefix.count))
            : title
    }

    // MARK: - Actions

    private func loadCurrentPlace() async {
        let status = await locationService.requestPermission()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard let location = try? await locationService.currentLocation() else { return }
        currentPlace = await locationService.placeName(for: location)
    }

    /// Removes every visit-history record for a place.
    private func deleteVisited(named name: String) {
        let toDelete = history.filter {
            $0.type == .locationVisited && placeName(from: $0.title) == name
        }
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
        showToast("Location removed")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

struct LocationCardView: View {
    var iconName: String
    var title: String
    var subtitle: String
    var address: String?
    var recentlyEdited: Bool = false
    var reminders: [String]
    var extraCount: Int = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color(hex: "#E8F3FF")

            // Large background icon
            VStack {
                Image(systemName: iconName)
                    .font(.system(size: 110))
                    .foregroundColor(Color(hex: "#C4D7EA"))
                    .offset(x: -30, y: 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#1D3557"))

                    if let address = address {
                        Text(address)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#94A8BC"))
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }

                    Spacer()

                    if recentlyEdited {
                        Text("Current")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#4F83AB"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#3FA9F5").opacity(0.15))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: "#4F83AB"), lineWidth: 1)
                            )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#94A8BC"))
                    .padding(.bottom, 8)

                ForEach(reminders, id: \.self) { reminder in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: "#4A60B2"))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(Color(hex: "#94A8BC").opacity(0.5), lineWidth: 1)
                            )
                        Text(reminder)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                    }
                }

                if extraCount > 0 {
                    Text("+\(extraCount) more")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#368BC8"))
                        .padding(.leading, 22)
                        .padding(.top, 4)
                }
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
    .modelContainer(for: HistoryItem.self, inMemory: true)
}
