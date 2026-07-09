//
//  AddLocationSheet.swift
//  Eve
//
//  Map-based "Add Location" picker, styled after the Apple Reminders location
//  screen: name the place, search an address, pick from live results, confirm
//  on a map with a pin. Deliberately has no Arriving/Leaving (geofence-trigger)
//  options and no "Getting in/out of Car" rows — this only picks a place.
//
//  The place's icon is chosen automatically on save: MapKit's point-of-interest
//  category when the pin has one, otherwise the on-device Foundation Model
//  classifies it from the name/address in the background (LocationIconResolver).
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import Observation

/// Wraps `MKLocalSearchCompleter` so the view gets live autocomplete results as
/// the user types. Main-actor isolated to match the app's default isolation;
/// the completer's delegate callbacks arrive on the main thread.
@MainActor
@Observable
final class LocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {

    var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            results = []
        }
    }
}

struct AddLocationSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var nextSortOrder: Int = 0

    @State private var completer = LocationSearchCompleter()
    @State private var locationService = LocationService()

    private let foundationModel = FoundationModelService()

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// The name the place will be saved under — always visible at the top so
    /// the user names the place themselves. Picking a search result only
    /// fills this when it's still empty; a typed name is never overwritten.
    @State private var placeName = ""

    // The chosen place, once resolved to real coordinates.
    @State private var selectedTitle: String?
    @State private var selectedName: String?
    @State private var selectedAddress: String?
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    /// MapKit's own category for the confirmed pin (restaurant, gym, …).
    /// When present it decides the icon outright; when nil the on-device
    /// model classifies from the names/address instead — see `save()`.
    @State private var selectedCategory: MKPointOfInterestCategory?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                nameField

                searchField

                List {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        row(
                            icon: "location.fill",
                            iconColor: Color(hex: "#94A8BC"),
                            title: "Current Location",
                            subtitle: "Use where you are now",
                            selected: false
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(completer.results.enumerated()), id: \.offset) { _, completion in
                        Button {
                            select(completion)
                        } label: {
                            row(
                                icon: "mappin.circle.fill",
                                iconColor: Color(hex: "#FF4245"),
                                title: completion.title,
                                subtitle: completion.subtitle,
                                selected: completion.title == selectedTitle
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)

                if let coordinate = selectedCoordinate {
                    Map(position: $cameraPosition) {
                        Marker(placeName.isEmpty ? (selectedName ?? "Selected place") : placeName, coordinate: coordinate)
                            .tint(Color(hex: "#FF4245"))
                    }
                    .frame(height: 220)
                    .transition(.move(edge: .bottom))
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selectedCoordinate == nil || placeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { searchFocused = true }
        }
    }

    // MARK: - Subviews

    private var nameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundColor(Color(hex: "#94A8BC"))
            TextField("Place name", text: $placeName)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(hex: "#E8F3FF"))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(hex: "#94A8BC"))
            TextField("Search or Enter Address", text: $searchText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    completer.update(query: newValue)
                }
            if isResolving {
                ProgressView()
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    completer.update(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(hex: "#94A8BC"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(hex: "#E8F3FF"))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func row(icon: String, iconColor: Color, title: String, subtitle: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "#1D3557"))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#94A8BC"))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#368BC8"))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// Resolves a completion to real coordinates and recenters the map on it.
    private func select(_ completion: MKLocalSearchCompletion) {

        selectedTitle = completion.title
        searchFocused = false
        isResolving = true

        Task {
            defer { isResolving = false }

            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }

            selectedCategory = item.pointOfInterestCategory

            apply(
                name: item.name ?? completion.title,
                address: item.placemark.title ?? completion.subtitle,
                coordinate: item.placemark.coordinate
            )
        }
    }

    private func useCurrentLocation() async {

        let status = await locationService.requestPermission()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }

        isResolving = true
        defer { isResolving = false }

        guard let location = try? await locationService.currentLocation() else { return }

        let name = await locationService.placeName(for: location) ?? "Current Location"

        selectedTitle = nil
        selectedCategory = nil
        searchFocused = false
        apply(name: name, address: nil, coordinate: location.coordinate)
    }

    private func apply(name: String, address: String?, coordinate: CLLocationCoordinate2D) {
        selectedName = name
        // Fill the name field from the picked place only when the user
        // hasn't named it themselves — a typed name is never overwritten.
        if placeName.trimmingCharacters(in: .whitespaces).isEmpty {
            placeName = name
        }
        selectedAddress = address
        selectedCoordinate = coordinate
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }

    private func save() {

        guard let coordinate = selectedCoordinate else { return }

        let name = placeName.trimmingCharacters(in: .whitespacesAndNewlines)

        // MapKit's category decides the icon outright when it knows the
        // place; otherwise save with the default pin and let the on-device
        // model refine it in the background below.
        let categoryIcon = LocationIconResolver.icon(for: selectedCategory)

        let location = SavedLocation(
            name: name.isEmpty ? (selectedName ?? searchText) : name,
            address: selectedAddress,
            iconName: categoryIcon ?? LocationIconResolver.defaultIcon,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            sortOrder: nextSortOrder
        )

        modelContext.insert(location)
        try? modelContext.save()

        if categoryIcon == nil {
            // Deliberately unstructured so it outlives the sheet's dismissal
            // below. SavedLocation is observable, so the chip's icon updates
            // live when the classification lands; any failure (model
            // unavailable, non-English name, junk output) just keeps the pin.
            let context = modelContext
            let mapName = selectedName
            let address = selectedAddress

            Task {
                guard let icon = try? await foundationModel.classifyPlaceIcon(
                    userName: location.name,
                    mapName: mapName,
                    address: address
                ), icon != location.iconName else { return }

                location.iconName = icon
                try? context.save()
            }
        }

        dismiss()
    }
}

#Preview {
    AddLocationSheet()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
