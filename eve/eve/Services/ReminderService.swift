//
//  ReminderService.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import EventKit

final class ReminderService {

    private let eventStore: EKEventStore

    /// Injecting the store keeps this service testable:
    /// tests (or previews) can pass a fake/shared store.
    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    /// Returns false if the user denied access (EventKit does not throw on denial).
    @discardableResult
    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    /// Fetches incomplete reminders due within a window around now
    /// (default: 33 days back, 33 days ahead).
    ///
    /// Reminders with no due date are always included: passing dates to
    /// EventKit's predicate would silently exclude them, so we fetch all
    /// incomplete reminders and apply the window ourselves.
    func fetchIncompleteReminders(
        daysBefore: Int = 33,
        daysAfter: Int = 33
    ) async -> [ReminderItem] {

        let now = Date()

        let start = Calendar.current.date(
            byAdding: .day,
            value: -daysBefore,
            to: now
        )!

        let end = Calendar.current.date(
            byAdding: .day,
            value: daysAfter,
            to: now
        )!

        let all: [ReminderItem] = await withCheckedContinuation { continuation in

            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )

            eventStore.fetchReminders(matching: predicate) { reminders in

                let items = reminders?.map {
                    ReminderItem(reminder: $0)
                } ?? []

                continuation.resume(returning: items)

            }

        }

        return all.filter { item in

            guard let dueDate = item.dueDate else { return true }

            return dueDate >= start && dueDate <= end

        }

    }

}
