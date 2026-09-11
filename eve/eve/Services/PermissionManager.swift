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
  var isCalendarGranted: Bool = false
  var isNotificationsGranted: Bool = false
  var isAIEnabled: Bool = false
  var hasCompletedOnboarding: Bool = false

  private let locationManager = CLLocationManager()
  private let eventStore = EKEventStore()
  private var locationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

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
    isCalendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      // Completion runs off the main actor; hop back on to touch state.
      Task { @MainActor in
        self.isNotificationsGranted = Self.canDeliverNotifications(settings.authorizationStatus)
      }
    }
  }

  static func canDeliverNotifications(_ status: UNAuthorizationStatus) -> Bool {
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
    let status = await requestLocationIfUndetermined()
    guard status == .authorizedWhenInUse else { return }
    locationManager.requestAlwaysAuthorization()
  }

  func requestLocation() {
    locationManager.requestAlwaysAuthorization()
  }

  func requestCalendar() async {
    do {
      // Method is main-actor isolated, so we resume on main after await.
      isCalendarGranted = try await eventStore.requestFullAccessToEvents()
    } catch {
      print("Failed to request calendar access: \(error)")
    }
  }

  func requestNotifications() async {
    do {
      isNotificationsGranted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
    } catch {
      print("Failed to request notification access: \(error)")
    }
  }

  func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func requestNotificationsIfUndetermined() async -> UNAuthorizationStatus {
    let status = await notificationAuthorizationStatus()
    guard status == .notDetermined else {
      isNotificationsGranted = Self.canDeliverNotifications(status)
      return status
    }
    await requestNotifications()
    let updatedStatus = await notificationAuthorizationStatus()
    isNotificationsGranted = Self.canDeliverNotifications(updatedStatus)
    return updatedStatus
  }

  func enableAI() {
    isAIEnabled = true
    UserDefaults.standard.set(true, forKey: "isAIEnabled")
  }

  /// The one permission onboarding asks for: Calendar.
  ///
  /// Eve builds the routine from calendar events, so that is the only access
  /// it needs before the app is useful. Everything else is requested at the
  /// point of use instead of being stacked up behind one Next button:
  ///
  /// - Location — when the user adds a place (`AddLocationSheet`), which is
  ///   the moment a place-based reminder actually becomes possible.
  /// - Notifications — the first time Eve schedules something to deliver
  ///   (`NotificationService.scheduleReminder`).
  ///
  /// Reminders-app access is gone entirely: Eve reads the calendar only.
  func requestOnboardingPermissions() async {
    enableAI()            // app-level consent (no OS prompt exists)
    await requestCalendar()
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
      if manager.authorizationStatus != .notDetermined {
        locationContinuation?.resume(returning: manager.authorizationStatus)
        locationContinuation = nil
      }
    }
  }
}
