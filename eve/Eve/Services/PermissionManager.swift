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
  var isReminderGranted: Bool = false
  var hasCompletedOnboarding: Bool = false

  private let locationManager = CLLocationManager()
  private let eventStore = EKEventStore()

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
    isReminderGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      // Completion runs off the main actor; hop back on to touch state.
      Task { @MainActor in
        self.isNotificationsGranted = (settings.authorizationStatus == .authorized)
      }
    }
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

  func requestReminders() async {
    do {
      isReminderGranted = try await eventStore.requestFullAccessToReminders()
    } catch {
      print("Failed to request reminder access: \(error)")
    }
  }

  func enableAI() {
    isAIEnabled = true
    UserDefaults.standard.set(true, forKey: "isAIEnabled")
  }

  /// Requests every permission the app needs, in turn. Called from the
  /// onboarding Next button: the informational PermissionView explains what
  /// each is for, and this fires the actual OS prompts when the user proceeds.
  /// iOS presents the system alerts one at a time.
  func requestAllPermissions() async {
    enableAI()                          // app-level consent (no OS prompt exists)
    requestLocation()                   // prompt shown; result arrives via delegate
    await requestNotifications()
    await requestCalendar()
    await requestReminders()
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
    }
  }
}
