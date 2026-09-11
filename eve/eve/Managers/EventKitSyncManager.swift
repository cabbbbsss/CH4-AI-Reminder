//
//  EventKitSyncManager.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import EventKit
import SwiftData

/// Keeps the SwiftData mirror of the user's Calendar fresh.
///
/// - Performs the initial ±33-day import.
/// - Listens for `.EKEventStoreChanged` and resyncs automatically when
///   the user adds/edits/deletes anything in the Calendar app.
///
/// Eve reads calendar events only. It used to mirror the Reminders app too,
/// which meant a second system prompt the moment the dashboard opened; that
/// data is no longer part of the product.
/// - Diffs incoming data against the local mirror so History can record
///   what actually changed instead of blind re-imports.
@Observable
final class EventKitSyncManager {

    private(set) var lastSync: Date?

    /// nil until the permission dialog has been answered.
    private(set) var hasCalendarAccess: Bool?

    private let calendarService: CalendarService
    private let historyLogger: HistoryLogger
    private let context: ModelContext

    private var observationTask: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?

    /// The adaptive notification coordinator attaches here so an EventKit
    /// change updates pending alerts after the SwiftData mirror is saved.
    var onSyncCompleted: (() async -> Void)?

    init(context: ModelContext) {

        self.calendarService = CalendarService(eventStore: EKEventStore())
        self.historyLogger = HistoryLogger(context: context)
        self.context = context

    }

    /// Requests access, runs the first sync, then starts listening for changes.
    ///
    /// Split into two callable halves below so onboarding's learning log can
    /// show connecting and importing as separate steps — and, more usefully,
    /// tell "we couldn't get access" apart from "we got access and your
    /// calendar was empty", which this one call used to collapse together.
    func start() async {
        guard await requestAccess() else { return }
        await beginSyncing()
    }

    /// Asks for Calendar access and records the answer.
    @discardableResult
    func requestAccess() async -> Bool {
        hasCalendarAccess = (try? await calendarService.requestAccess()) ?? false
        return hasCalendarAccess == true
    }

    /// Imports the calendar and starts watching for changes. A no-op without
    /// access, so it is always safe to call after `requestAccess()`.
    func beginSyncing() async {

        guard hasCalendarAccess == true else { return }

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

        try? context.save()

        lastSync = .now

        await onSyncCompleted?()

        // Only write History when something actually changed,
        // so the timeline stays meaningful.
        if !summaries.isEmpty {

            try? historyLogger.log(
                .calendarImported,
                title: "Calendar synced",
                detail: summaries.joined(separator: " · ")
            )

        }

    }

    // MARK: - Change observation

    private func startObserving() {

        observationTask?.cancel()

        observationTask = Task { [weak self] in

            // iOS posts this for ANY change in the EventKit database, made
            // by any app. It doesn't say what changed, so the response is
            // always a re-fetch.
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
                    || current.location != event.location
                    || current.attendees != event.attendees
                    || current.meetingURL != event.meetingURL
                    || current.isAllDay != event.isAllDay
                    || current.latitude != event.latitude
                    || current.longitude != event.longitude {

                    current.title = event.title
                    current.startDate = event.startDate
                    current.endDate = event.endDate
                    current.notes = event.notes
                    current.location = event.location
                    current.attendees = event.attendees
                    current.meetingURL = event.meetingURL

                    current.isAllDay = event.isAllDay
                    current.latitude = event.latitude
                    current.longitude = event.longitude

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

    deinit {
        observationTask?.cancel()
        pendingSync?.cancel()
    }

}
