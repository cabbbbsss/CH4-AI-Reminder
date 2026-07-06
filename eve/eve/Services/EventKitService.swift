import Foundation
import EventKit
import Observation

@Observable
final class EventKitService {
  static let shared = EventKitService()
  private let eventStore = EKEventStore()
  
  var upcomingEvents: [EKEvent] = []
  var activeReminders: [EKReminder] = []
  
  func fetchUpcomingEvents() {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
    
    let calendars = eventStore.calendars(for: .event)
    let startDate = Date()
    let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
    
    let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
    let events = eventStore.events(matching: predicate)
    
    DispatchQueue.main.async {
      self.upcomingEvents = events.sorted { $0.startDate < $1.startDate }
    }
  }
  
  func fetchReminders() {
    guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
    
    let calendars = eventStore.calendars(for: .reminder)
    let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
    
    eventStore.fetchReminders(matching: predicate) { reminders in
      DispatchQueue.main.async {
        self.activeReminders = reminders ?? []
      }
    }
  }
}
