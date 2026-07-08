import Foundation
import CoreLocation
import EventKit
import UserNotifications
import Observation

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
    isLocationGranted = locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
    isCalendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        self.isNotificationsGranted = (settings.authorizationStatus == .authorized)
      }
    }
    
    self.isAIEnabled = UserDefaults.standard.bool(forKey: "isAIEnabled")
    self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
  }
  
  func requestLocation() {
    locationManager.requestAlwaysAuthorization()
  }
  
  func requestCalendar() async {
    do {
      let granted = try await eventStore.requestFullAccessToEvents()
      DispatchQueue.main.async { self.isCalendarGranted = granted }
    } catch {
      print("Failed to request calendar access: \(error)")
    }
  }
  
  func requestNotifications() async {
    do {
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
      DispatchQueue.main.async { self.isNotificationsGranted = granted }
    } catch {
      print("Failed to request notification access: \(error)")
    }
  }
  
  func requestReminders() async {
    do {
      let granted = try await eventStore.requestFullAccessToReminders()
      DispatchQueue.main.async { self.isReminderGranted = granted }
    } catch  {
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
  
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    isLocationGranted = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
  }
}
