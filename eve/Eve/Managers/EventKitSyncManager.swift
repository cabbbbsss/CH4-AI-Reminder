//
//  EventKitSyncManager.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import EventKit
import SwiftData

/// Keeps the SwiftData mirror of Calendar & Reminders fresh.
///
/// - Performs the initial ±33-day import.
/// - Listens for `.EKEventStoreChanged` and resyncs automatically when
///   the user adds/edits/deletes anything in the Calendar or Reminders apps.
/// - Diffs incoming data against the local mirror so History can record
///   what actually changed instead of blind re-imports.
@Observable
final class EventKitSyncManager {

    private(set) var lastSync: Date?

    /// nil until the permission dialogs have been answered.
    private(set) var hasCalendarAccess: Bool?
    private(set) var hasReminderAccess: Bool?

    private let calendarService: CalendarService
    private let reminderService: ReminderService
    private let historyLogger: HistoryLogger
    private let context: ModelContext

    private var observationTask: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?

    init(context: ModelContext) {

        // One shared store: both services talk to the same EventKit
        // connection, and iOS posts one change-notification stream for it.
        let sharedStore = EKEventStore()

        self.calendarService = CalendarService(eventStore: sharedStore)
        self.reminderService = ReminderService(eventStore: sharedStore)
        self.historyLogger = HistoryLogger(context: context)
        self.context = context

    }

    /// Requests access, runs the first sync, then starts listening for changes.
    func start() async {

        hasCalendarAccess = (try? await calendarService.requestAccess()) ?? false
        hasReminderAccess = (try? await reminderService.requestAccess()) ?? false

        guard hasCalendarAccess == true || hasReminderAccess == true else { return }

        await syncNow()

        startObserving()

    }

    func syncNow() async {

        var summaries: [String] = []

        if hasCalendarAccess == true {

            let incoming = calendarService.fetchEvents()

            if let summary = syncEvents(incoming) {
                summaries.append(summary)
            }

        }

        if hasReminderAccess == true {

            let incoming = await reminderService.fetchIncompleteReminders()

            if let summary = syncReminders(incoming) {
                summaries.append(summary)
            }

        }

        try? context.save()

        lastSync = .now

        // Only write History when something actually changed,
        // so the timeline stays meaningful.
        if !summaries.isEmpty {

            try? historyLogger.log(
                .calendarImported,
                title: "Calendar & Reminders synced",
                detail: summaries.joined(separator: " · ")
            )

        }

    }

    // MARK: - Change observation

    private func startObserving() {

        observationTask?.cancel()

        observationTask = Task { [weak self] in

            // iOS posts this for ANY change in the EventKit database —
            // events or reminders, made by any app. It doesn't say what
            // changed, so the response is always a re-fetch.
            let changes = NotificationCenter.default.notifications(
                named: .EKEventStoreChanged
            )

            for await _ in changes {
                self?.scheduleSync()
            }

        }

    }

    /// EventKit often posts several notifications for one user action.
    /// Debounce: restart a short timer each time, sync once things settle.
    private func scheduleSync() {

        pendingSync?.cancel()

        pendingSync = Task { [weak self] in

            try? await Task.sleep(for: .seconds(1))

            guard !Task.isCancelled else { return }

            await self?.syncNow()

        }

    }

    // MARK: - Diffing

    private func syncEvents(_ incoming: [CalendarEvent]) -> String? {

        let existing = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []

        var byID = Dictionary(
            existing.map { ($0.occurrenceID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var added = 0
        var updated = 0

        for event in incoming {

            if let current = byID.removeValue(forKey: event.occurrenceID) {

                if current.title != event.title
                    || current.startDate != event.startDate
                    || current.endDate != event.endDate
                    || current.notes != event.notes
                    || current.location != event.location {

                    current.title = event.title
                    current.startDate = event.startDate
                    current.endDate = event.endDate
                    current.notes = event.notes
                    current.location = event.location

                    updated += 1

                }

            } else {

                context.insert(event)

                added += 1

            }

        }

        // Whatever is left locally no longer exists in the window: prune it.
        let removed = byID.count

        for orphan in byID.values {
            context.delete(orphan)
        }

        guard added + updated + removed > 0 else { return nil }

        return "Events: \(added) added, \(updated) updated, \(removed) removed"

    }

    private func syncReminders(_ incoming: [ReminderItem]) -> String? {

        let existing = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        var byID = Dictionary(
            existing.map { ($0.reminderIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var added = 0
        var updated = 0

        for reminder in incoming {

            if let current = byID.removeValue(forKey: reminder.reminderIdentifier) {

                if current.title != reminder.title
                    || current.dueDate != reminder.dueDate
                    || current.notes != reminder.notes
                    || current.location != reminder.location {

                    current.title = reminder.title
                    current.dueDate = reminder.dueDate
                    current.notes = reminder.notes
                    current.location = reminder.location

                    updated += 1

                }

            } else {

                context.insert(reminder)

                added += 1

            }

        }

        let removed = byID.count

        for orphan in byID.values {
            context.delete(orphan)
        }

        guard added + updated + removed > 0 else { return nil }

        return "Reminders: \(added) added, \(updated) updated, \(removed) removed"

    }

    deinit {
        observationTask?.cancel()
        pendingSync?.cancel()
    }

}
