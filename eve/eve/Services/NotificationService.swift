//
//  NotificationService.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import UserNotifications
import CoreLocation

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

    /// Returns false if the user denied notifications.
    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
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

    /// Whether Eve may post notifications, asking if it hasn't been decided.
    ///
    /// `mayPrompt` is the important half. Onboarding only requests Calendar,
    /// so the notification prompt lives here — but it must only appear off the
    /// back of something the user just did. A background resync asking for
    /// permission suspends until the prompt is answered, which on first launch
    /// stalls everything queued behind it, so housekeeping passes false and
    /// simply schedules nothing until permission exists.
    private func isAllowed(mayPrompt: Bool) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return mayPrompt ? await requestPermission() : false
        default:
            return false
        }
    }

    /// Schedules an adaptive reminder.
    /// Pass a date for a timed reminder; nil delivers in ~5 seconds
    /// (useful for "right now" moments and for testing).
    /// - Parameter mayPrompt: whether an undecided user may be asked now.
    ///   True for something they just did; false for background work.
    func scheduleReminder(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        at date: Date? = nil,
        mayPrompt: Bool = true
    ) async throws {

        // Nothing would be delivered anyway, and adding the request would
        // hide that fact.
        guard await isAllowed(mayPrompt: mayPrompt) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger: UNNotificationTrigger

        if let date {

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )

            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

        } else {

            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 5,
                repeats: false
            )

        }

        try await center.add(
            UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )
        )

    }

    func cancelReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "EVE notifications are active"
        content.body = "This is a five-second local delivery test."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: "eve.adaptive.test",
            content: content,
            trigger: trigger
        ))
    }

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
        try await center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNLocationNotificationTrigger(region: region, repeats: true)
        ))
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, iOS silently hides notifications while Eve is
    /// in the foreground — fatal for a reminder app.
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

    // MARK: - TEMPORARY: Notification preview demo
    //
    // A throwaway helper so you can *see* what a reminder notification looks
    // like without waiting for a real event/reminder/location trigger. It
    // pre-schedules a batch of one-shot notifications 10s apart (iOS won't let
    // a single trigger repeat faster than 60s), cycling through one sample of
    // each kind Eve sends. They fire whether Eve is foregrounded, backgrounded,
    // or the phone is locked. Delete this whole section when the demo is no
    // longer needed — nothing else depends on it.

    /// One sample notification per reminder type (event / reminder / location).
    private static let demoSamples: [(title: String, body: String)] = [
        ("Design Review at 3:00 PM",
         "Your meeting starts in 1 hour. Leave by 2:30 to arrive on time."),
        ("Reminder: Submit expense report",
         "This is due today — don't let it slip."),
        ("You're near Whole Foods",
         "Grab milk and eggs while you're here — they're on your list.")
    ]

    private static let demoIDPrefix = "demo-preview-"

    /// Schedules `count` one-shot notifications `interval` seconds apart,
    /// cycling through `demoSamples`. Re-calling re-arms a fresh batch.
    func startDemoNotifications(count: Int = 30, interval: TimeInterval = 10) async {
        _ = await requestPermission()
        cancelDemoNotifications()

        for i in 0..<count {
            let sample = Self.demoSamples[i % Self.demoSamples.count]

            let content = UNMutableNotificationContent()
            content.title = sample.title
            content.body = sample.body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Double(i + 1) * interval,
                repeats: false
            )

            try? await center.add(
                UNNotificationRequest(
                    identifier: "\(Self.demoIDPrefix)\(i)",
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    /// Cancels every pending demo notification (iOS caps pending at 64).
    func cancelDemoNotifications() {
        let ids = (0..<64).map { "\(Self.demoIDPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

}
