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

  // Whether we've already prompted for each permission. Once asked, we
  // don't offer to ask again — the user must change it in Settings.
  var didAskLocation: Bool = false
  var didAskNotifications: Bool = false
  var didAskCalendar: Bool = false

  private let locationManager = CLLocationManager()
  private let eventStore = EKEventStore()

  override init() {
    super.init()
    locationManager.delegate = self
    checkInitialStatus()
  }

  private func checkInitialStatus() {
    isLocationGranted = locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
    isCalendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      // Completion runs off the main actor; hop back on to touch state.
      Task { @MainActor in
        self.isNotificationsGranted = (settings.authorizationStatus == .authorized)
      }
    }

    self.isAIEnabled = UserDefaults.standard.bool(forKey: "isAIEnabled")
    self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    self.didAskLocation = UserDefaults.standard.bool(forKey: "didAskLocation")
    self.didAskNotifications = UserDefaults.standard.bool(forKey: "didAskNotifications")
    self.didAskCalendar = UserDefaults.standard.bool(forKey: "didAskCalendar")
  }

  func requestLocation() {
    didAskLocation = true
    UserDefaults.standard.set(true, forKey: "didAskLocation")
    locationManager.requestAlwaysAuthorization()
  }

  func requestCalendar() async {
    didAskCalendar = true
    UserDefaults.standard.set(true, forKey: "didAskCalendar")
    do {
      // Method is main-actor isolated, so we resume on main after await.
      isCalendarGranted = try await eventStore.requestFullAccessToEvents()
    } catch {
      print("Failed to request calendar access: \(error)")
    }
  }

  func requestNotifications() async {
    didAskNotifications = true
    UserDefaults.standard.set(true, forKey: "didAskNotifications")
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
