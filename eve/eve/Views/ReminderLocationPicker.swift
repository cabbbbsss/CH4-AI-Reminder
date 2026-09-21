//
//  ReminderLocationPicker.swift
//  Eve
//
//  The Location screen the Details sheet pushes: where you are now, live
//  search results, a tick on the one you chose, and Arriving/Leaving once
//  there is something to attach it to. It doesn't save anything itself —
//  the choice goes back through the binding and the Details sheet turns it
//  into a `SavedLocation` when the reminder is saved.
//

import SwiftUI
import MapKit
import CoreLocation

/// A place chosen for a reminder, before it is a `SavedLocation`.
///
/// Kept as a value so the Details sheet can compare it for unsaved changes
/// and drop it on ✕ without ever having inserted anything into the store.
struct ReminderPlace: Equatable {

    /// Set when the pick came from a place that is already saved, so saving
    /// the reminder reuses that row instead of minting a duplicate.
    var savedID: UUID?

    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    /// MapKit's category for the pin, when it has one — decides the icon.
    var category: MKPointOfInterestCategory?
}

struct ReminderLocationPicker: View {

    @Binding var place: ReminderPlace?
    @Binding var trigger: LocationTrigger

    @Environment(\.openURL) private var openURL

    @State private var completer = LocationSearchCompleter()
    @State private var locationService = LocationService()

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// Which result row is ticked. Completions aren't identifiable across
    /// updates, so this is the title+subtitle pair rather than the object.
    @State private var selectedKey: String?

    @State private var isResolving = false

    private enum CurrentLocation: Equatable {
        case unknown
        case resolving
        case resolved(name: String, address: String?, coordinate: CLLocationCoordinate2D)
        case denied

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown), (.resolving, .resolving), (.denied, .denied):
                return true
            case let (.resolved(a, b, _), .resolved(c, d, _)):
                return a == c && b == d
            default:
                return false
            }
        }
    }

    @State private var current: CurrentLocation = .unknown

    var body: some View {
        ZStack {
            AuroraBackground()

            List {
                currentLocationRow

                ForEach(Array(completer.results.enumerated()), id: \.offset) { _, completion in
                    resultRow(completion)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        // Back button as a bare chevron: the editor role drops the previous
        // screen's title from it, and keeps the swipe-back that hiding the
        // button outright would lose.
        .toolbarRole(.editor)
        // The search field lives at the bottom, above the keyboard, and gives
        // way to Arriving/Leaving once there's a place for it to describe.
        .safeAreaInset(edge: .bottom) {
            Group {
                if place == nil {
                    searchField
                } else {
                    triggerControl
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .onAppear {
            selectedKey = nil
            // If the user already granted location, show where they are
            // straight away. If not, the row asks on tap — the permission
            // prompt belongs to a tap, not to a screen appearing.
            let status = locationService.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                Task { await resolveCurrentLocation() }
            } else if status == .denied || status == .restricted {
                current = .denied
            }
        }
        // Focus after the push has landed: asking on appear, while the
        // field is still sliding in, is sometimes ignored.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if place == nil {
                searchFocused = true
            }
        }
    }

    // MARK: - Rows

    private var currentLocationRow: some View {
        Button {
            Task { await useCurrentLocation() }
        } label: {
            row(
                icon: "location.circle.fill",
                title: "Current Location",
                subtitle: currentSubtitle,
                selected: isCurrentSelected
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        // No rule above the first row — nothing to separate it from.
        .listRowSeparator(.hidden, edges: .top)
    }

    private var currentSubtitle: String {
        switch current {
        case .unknown: return "Use where you are now"
        case .resolving: return "Finding you…"
        case let .resolved(_, address, _): return address ?? "Use where you are now"
        case .denied: return "Location access is off — open Settings"
        }
    }

    private var isCurrentSelected: Bool {
        guard case let .resolved(name, _, coordinate) = current, let place else { return false }
        return place.name == name
            && place.latitude == coordinate.latitude
            && place.longitude == coordinate.longitude
    }

    private func resultRow(_ completion: MKLocalSearchCompletion) -> some View {
        let key = completion.title + "\n" + completion.subtitle
        return Button {
            if selectedKey == key {
                // Tapping the tick again clears it, which brings the search
                // field back — otherwise there's no way to look for another.
                selectedKey = nil
                place = nil
                searchFocused = true
            } else {
                select(completion, key: key)
            }
        } label: {
            row(
                icon: "mappin.circle.fill",
                title: completion.title,
                subtitle: completion.subtitle,
                selected: selectedKey == key
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func row(icon: String, title: String, subtitle: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.eveOnSurfaceFaint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.eveBody)
                    .foregroundStyle(Color.eveOnSurface)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.eveDetail)
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if selected {
                Image(systemName: "checkmark")
                    .font(.eveBody.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Bottom controls

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.eveOnSurfaceMuted)

            TextField("Search or Enter Address", text: $searchText)
                .font(.eveBody)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: searchText) { _, query in
                    completer.update(query: query)
                }

            if isResolving {
                ProgressView()
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.eveOnSurfaceFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 48)
        .background(Color.eveSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var triggerControl: some View {
        Picker("Remind me when", selection: $trigger) {
            ForEach(LocationTrigger.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Resolving

    /// Turns a completion into coordinates and an address, then ticks it.
    private func select(_ completion: MKLocalSearchCompletion, key: String) {
        searchFocused = false
        isResolving = true

        Task {
            defer { isResolving = false }

            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }

            let coordinate = item.location.coordinate
            let address = nonEmpty(item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true))
                ?? nonEmpty(item.address?.fullAddress)
                ?? nonEmpty(completion.subtitle)

            selectedKey = key
            place = ReminderPlace(
                name: item.name ?? completion.title,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                category: item.pointOfInterestCategory
            )
        }
    }

    private func useCurrentLocation() async {
        if case .denied = current {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            return
        }

        if case let .resolved(name, address, coordinate) = current {
            choose(name: name, address: address, coordinate: coordinate)
            return
        }

        let status = await locationService.requestPermission()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            current = .denied
            return
        }

        await resolveCurrentLocation()

        if case let .resolved(name, address, coordinate) = current {
            choose(name: name, address: address, coordinate: coordinate)
        }
    }

    private func resolveCurrentLocation() async {
        current = .resolving

        guard let location = try? await locationService.currentLocation() else {
            current = .unknown
            return
        }

        let details = await locationService.placeDetails(for: location)
        current = .resolved(
            name: details.name ?? "Current Location",
            address: details.address,
            coordinate: location.coordinate
        )
    }

    private func choose(name: String, address: String?, coordinate: CLLocationCoordinate2D) {
        selectedKey = nil
        searchFocused = false
        place = ReminderPlace(
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }
}

#Preview {
    NavigationStack {
        ReminderLocationPicker(place: .constant(nil), trigger: .constant(.arriving))
    }
}
