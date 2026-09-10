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

    /// Delivers any reminder pinned to the place the user just arrived at.
    private let scheduler: ReminderScheduler

    private var monitoringTask: Task<Void, Never>?

    /// Where the user was before the current place.
    ///
    /// Needed for "leaving": a place change is simultaneously a departure from
    /// one coordinate and an arrival at another, and the departure can only be
    /// matched against where they *were*.
    private var previousCoordinate: CLLocationCoordinate2D?

    init(
        context: ModelContext,
        locationService: LocationService = LocationService()
    ) {
        self.locationService = locationService
        self.historyLogger = HistoryLogger(context: context)
        self.scheduler = ReminderScheduler(context: context)
    }

    /// Begins monitoring, but only when location access has already been
    /// granted — this never shows the system prompt.
    ///
    /// The prompt belongs to the moment the user creates a place-based
    /// reminder (`AddLocationSheet`), not to opening the dashboard. Asking
    /// here would put the location dialog in front of every user on first
    /// launch, which is exactly what taking it out of onboarding avoided.
    /// Monitoring picks up on the next start once access is granted.
    func start() async {

        let status = locationService.authorizationStatus

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            accessDenied = status == .denied || status == .restricted
            return
        }

        // Baseline: know where we are, but don't log it —
        // "app launched" is not a visit, and would spam the timeline.
        if let location = try? await locationService.currentLocation() {
            currentPlace = await locationService.placeName(for: location)
            // Baseline, so the first change knows where it came from.
            previousCoordinate = location.coordinate
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

        // One move is two events: they have left wherever they were, and
        // arrived where they are. Matched on coordinates rather than `place`,
        // whose reverse-geocoded name won't reliably equal the name the user
        // gave the location themselves.
        if let previousCoordinate {
            await scheduler.deliver(
                trigger: .leaving,
                near: previousCoordinate.latitude,
                longitude: previousCoordinate.longitude
            )
        }

        await scheduler.deliver(
            trigger: .arriving,
            near: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        previousCoordinate = location.coordinate

    }

    deinit {
        monitoringTask?.cancel()
    }

}
