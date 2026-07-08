//
//  LocationActivityManager.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import CoreLocation
import SwiftData

/// Turns raw location changes into meaningful activity:
/// keeps track of the user's current place and records visits
/// in History so insights can be built from them later.
@Observable
final class LocationActivityManager {

    private(set) var currentPlace: String?

    private(set) var accessDenied = false

    private let locationService: LocationService

    private let historyLogger: HistoryLogger

    private var monitoringTask: Task<Void, Never>?

    init(
        context: ModelContext,
        locationService: LocationService = LocationService()
    ) {
        self.locationService = locationService
        self.historyLogger = HistoryLogger(context: context)
    }

    func start() async {

        let status = await locationService.requestPermission()

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            accessDenied = true
            return
        }

        // Baseline: know where we are, but don't log it —
        // "app launched" is not a visit, and would spam the timeline.
        if let location = try? await locationService.currentLocation() {
            currentPlace = await locationService.placeName(for: location)
        }

        monitoringTask?.cancel()

        monitoringTask = Task { [weak self] in

            guard let stream = self?.locationService.significantLocationChanges() else {
                return
            }

            for await location in stream {
                await self?.handleChange(to: location)
            }

        }

    }

    private func handleChange(to location: CLLocation) async {

        guard let place = await locationService.placeName(for: location) else {
            return
        }

        // Only a *change* of place is meaningful.
        guard place != currentPlace else { return }

        currentPlace = place

        try? historyLogger.log(
            .locationVisited,
            title: "Arrived near \(place)",
            detail: String(
                format: "%.3f, %.3f",
                location.coordinate.latitude,
                location.coordinate.longitude
            )
        )

    }

    deinit {
        monitoringTask?.cancel()
    }

}
