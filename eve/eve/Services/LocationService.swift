//
//  LocationService.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import CoreLocation
import MapKit

final class LocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()

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

    func currentLocation() async throws -> CLLocation {

        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }

    }

    func significantLocationChanges() -> AsyncStream<CLLocation> {

        AsyncStream { continuation in

            changeContinuation = continuation

            manager.startMonitoringSignificantLocationChanges()

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopMonitoring()
                }
            }

        }

    }

    private func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        changeContinuation = nil
    }

    func placeName(for location: CLLocation) async -> String? {

        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "en_US")
        let items = try? await request.mapItems
        let address = items?.first?.address
        return items?.first?.name ?? address?.shortAddress ?? address?.fullAddress

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
