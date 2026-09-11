import Foundation
import UserNotifications
import CoreLocation

/// App-owned gateway for every local notification. Keeping one delegate alive
/// is essential: a transient Settings/Home instance silently replaces the
/// previous delegate and loses notification actions.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let calendarPrefix = "eve.adaptive.calendar."
    static let locationPrefix = "eve.location.reminder."
    static let adaptiveCategory = "eve.adaptive.calendar"

    private let center = UNUserNotificationCenter.current()
    var onFeedback: ((String, NotificationFeedback) -> Void)?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: "done", title: "Done", options: []),
            UNNotificationAction(identifier: "tooEarly", title: "Too Early", options: []),
            UNNotificationAction(identifier: "tooLate", title: "Too Late", options: [])
        ]
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.adaptiveCategory,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
    }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func notificationSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }

    func schedule(_ plan: NotificationPlan) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = Self.adaptiveCategory
        content.userInfo = ["occurrenceID": plan.occurrenceID]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: plan.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
    }

    /// Kept for one-off assistant nudges that are not calendar plans.
    func scheduleReminder(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        at date: Date? = nil
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger: UNNotificationTrigger
        if let date {
            trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: date
                ),
                repeats: false
            )
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// The system monitors this region itself, so a persistent When In Use
    /// grant is sufficient even while EVE is not open.
    func scheduleLocationReminder(
        id: String,
        title: String,
        body: String,
        coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 200
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let region = CLCircularRegion(
            center: coordinate,
            radius: min(max(radius, 100), 1_000),
            identifier: id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "EVE notifications are active"
        content.body = "This is a five-second local delivery test."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(identifier: "eve.adaptive.test", content: content, trigger: trigger))
    }

    func cancelReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelLocationReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func pendingManagedRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.calendarPrefix) }
    }

    func cancelManagedRequests(except identifiers: Set<String>) async {
        let stale = await pendingManagedRequests().map(\.identifier).filter { !identifiers.contains($0) }
        guard !stale.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    func cancelLocationRequests(except identifiers: Set<String>) async {
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.locationPrefix) && !identifiers.contains($0) }
        guard !stale.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == Self.adaptiveCategory,
              let occurrenceID = response.notification.request.content.userInfo["occurrenceID"] as? String
        else { return }
        let feedback: NotificationFeedback?
        switch response.actionIdentifier {
        case "done": feedback = .done
        case "tooEarly": feedback = .tooEarly
        case "tooLate": feedback = .tooLate
        default: feedback = nil
        }
        guard let feedback else { return }
        await MainActor.run { self.onFeedback?(occurrenceID, feedback) }
    }
}
