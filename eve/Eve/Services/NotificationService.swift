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

    /// Schedules an adaptive reminder.
    /// Pass a date for a timed reminder; nil delivers in ~5 seconds
    /// (useful for "right now" moments and for testing).
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

}
