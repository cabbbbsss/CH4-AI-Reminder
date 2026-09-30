import Foundation
import CoreLocation
import EventKit
import UserNotifications
import Observation

/// Tracks and requests the app's permissions. Holds UI-facing state,
/// so it's isolated to the main actor; that also makes it Sendable,
/// which is why its async callbacks no longer need manual queue hops.
@MainActor
@Observable
final class PermissionManager: NSObject, CLLocationManagerDelegate {
  static let shared = PermissionManager()

  var isLocationGranted: Bool = false
  /// Place reminders fire through OS region monitoring, which only wakes EVE
  /// when the user granted Always. "While Using" registers the geofence but
  /// never delivers it once EVE leaves the foreground.
  var isAlwaysLocationGranted: Bool = false
  var isCalendarGranted: Bool = false
  /// nil until the first read lands, so the launch read is never mistaken
  /// for a change — Home resyncs when this turns deliverable.
  var notificationStatus: UNAuthorizationStatus?
  var isNotificationsGranted: Bool { notificationStatus.map(Self.canDeliverNotifications) ?? false }
  var isAIEnabled: Bool = false
  var hasCompletedOnboarding: Bool = false

  private let locationManager = CLLocationManager()
  private var locationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
  private let hasRequestedAlwaysKey = "hasRequestedAlwaysLocation"

  override init() {
    super.init()
    locationManager.delegate = self
    checkInitialStatus()
  }

  private func checkInitialStatus() {
    refreshStatuses()

    self.isAIEnabled = UserDefaults.standard.bool(forKey: "isAIEnabled")
    self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
  }

  /// Re-reads the current OS authorization for every permission.
  /// Call this whenever the app returns to the foreground so that a change
  /// the user made in the Settings app is reflected immediately.
  func refreshStatuses() {
    isLocationGranted = locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
    isAlwaysLocationGranted = locationManager.authorizationStatus == .authorizedAlways
    isCalendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      // Completion runs off the main actor; hop back on to touch state.
      Task { @MainActor in
        self.notificationStatus = settings.authorizationStatus
      }
    }
  }

  nonisolated static func canDeliverNotifications(_ status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  func locationAuthorizationStatus() -> CLAuthorizationStatus {
    locationManager.authorizationStatus
  }

  /// Requests location only at the point a location reminder needs it.
  func requestLocationIfUndetermined() async -> CLAuthorizationStatus {
    let status = locationManager.authorizationStatus
    guard status == .notDetermined else { return status }

    return await withCheckedContinuation { continuation in
      locationContinuation = continuation
      locationManager.requestWhenInUseAuthorization()
    }
  }

  /// Elevates a previously granted foreground location permission only after
  /// the user explicitly enables adaptive background timing.
  func requestAdaptiveBackgroundLocation() async {
    await ensureAlwaysLocationForPlaceReminders()
  }

  /// Walks the user up to Always, which is what a place reminder needs to be
  /// delivered while EVE is closed.
  ///
  /// iOS only ever shows the Always upgrade prompt once, and it may defer it
  /// silently instead of presenting it — so this never suspends waiting for an
  /// answer. It asks on the first place reminder; on every later one, if the
  /// grant is still foreground-only, the only remaining route is Settings.
  func ensureAlwaysLocationForPlaceReminders() async {
    var status = locationManager.authorizationStatus
    if status == .notDetermined {
      status = await requestLocationIfUndetermined()
    }
    guard status == .authorizedWhenInUse else { return }

    guard !UserDefaults.standard.bool(forKey: hasRequestedAlwaysKey) else {
      PermissionRecoveryCoordinator.shared.presentBackgroundLocationRecovery()
      return
    }

    UserDefaults.standard.set(true, forKey: hasRequestedAlwaysKey)
    locationManager.requestAlwaysAuthorization()
  }

  func requestLocation() {
    locationManager.requestAlwaysAuthorization()
  }

  func requestNotifications() async {
    do {
      _ = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
    } catch {
      print("Failed to request notification access: \(error)")
    }
    notificationStatus = await notificationAuthorizationStatus()
  }

  func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func requestNotificationsIfUndetermined() async -> UNAuthorizationStatus {
    let status = await notificationAuthorizationStatus()
    guard status == .notDetermined else {
      notificationStatus = status
      return status
    }
    await requestNotifications()
    return notificationStatus ?? .notDetermined
  }

  func enableAI() {
    isAIEnabled = true
    UserDefaults.standard.set(true, forKey: "isAIEnabled")
  }

  func completeOnboarding() {
    hasCompletedOnboarding = true
    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
  }

  // Core Location's delegate protocol is nonisolated; step back onto
  // the main actor to update our isolated state.
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    MainActor.assumeIsolated {
      isLocationGranted = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
      isAlwaysLocationGranted = manager.authorizationStatus == .authorizedAlways
      if manager.authorizationStatus != .notDetermined {
        locationContinuation?.resume(returning: manager.authorizationStatus)
        locationContinuation = nil
      }
    }
  }
}
