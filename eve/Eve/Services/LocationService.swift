//
//  LocationService.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import CoreLocation

/// Bridges Core Location's delegate callbacks into async/await:
/// one-shot questions use continuations, ongoing monitoring uses AsyncStream.
final class LocationService: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    private let geocoder = CLGeocoder()

    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    private var locationContinuation: CheckedContinuation<CLLocation, any Error>?

    private var changeContinuation: AsyncStream<CLLocation>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Shows the permission dialog and suspends until the user answers.
    func requestPermission() async -> CLAuthorizationStatus {

        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus
        }

        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }

    }

    /// One-shot: where is the user right now?
    func currentLocation() async throws -> CLLocation {

        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }

    }

    /// Emits a location whenever iOS detects a significant move (~500 m+).
    /// Monitoring stops automatically when the consuming task is cancelled.
    func significantLocationChanges() -> AsyncStream<CLLocation> {

        AsyncStream { continuation in

            changeContinuation = continuation

            manager.startMonitoringSignificantLocationChanges()

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stopMonitoring()
                }
            }

        }

    }

    private func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        changeContinuation = nil
    }

    /// Turns raw coordinates into a human-readable place name.
    ///
    /// Reverse geocoding otherwise returns names in the *local* language of
    /// wherever the coordinates are, regardless of the device's UI language —
    /// e.g. Indonesian street/locality names even on an English-language
    /// device. That breaks the on-device Foundation Model, which rejects
    /// non-English input. Forcing an English locale here keeps the place
    /// name in a language the model can actually process.
    func placeName(for location: CLLocation) async -> String? {

        let placemark = try? await geocoder
            .reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US"))
            .first

        return placemark?.name ?? placemark?.locality

    }

    // MARK: - CLLocationManagerDelegate
    //
    // Core Location calls these on the thread the manager was created on
    // (main, here). The delegate protocol itself is nonisolated, so under
    // the project's default MainActor isolation we mark the methods
    // nonisolated and step back onto the main actor explicitly.

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        MainActor.assumeIsolated {

            guard manager.authorizationStatus != .notDetermined else { return }

            authContinuation?.resume(returning: manager.authorizationStatus)
            authContinuation = nil

        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {

            guard let latest = locations.last else { return }

            // A pending one-shot request takes priority;
            // otherwise the update belongs to the monitoring stream.
            if let continuation = locationContinuation {
                continuation.resume(returning: latest)
                locationContinuation = nil
            } else {
                changeContinuation?.yield(latest)
            }

        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

}
