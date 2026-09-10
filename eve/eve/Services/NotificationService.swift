//
//  NotificationService.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Returns false if the user denied notifications.
    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, iOS silently hides notifications while Eve is
    /// in the foreground — fatal for a reminder app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
