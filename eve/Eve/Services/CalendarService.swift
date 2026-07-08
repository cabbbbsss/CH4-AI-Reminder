//
//  CalendarService.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import EventKit

final class CalendarService {

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    /// Returns false if the user denied access (EventKit does not throw on denial).
    @discardableResult
    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    /// Fetches events in a window around now (default: 33 days back, 33 days ahead).
    func fetchEvents(
        daysBefore: Int = 33,
        daysAfter: Int = 33
    ) -> [CalendarEvent] {

        // Exclude read-only system calendars (Holidays, Birthdays): they're
        // auto-populated in the device's regional language regardless of
        // the app's own language settings, which breaks the on-device
        // model's language check when their titles end up in the AI prompt.
        let calendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)

        let now = Date()

        // Two steps: shift back N days, then snap to midnight.
        let start = Calendar.current.startOfDay(
            for: Calendar.current.date(
                byAdding: .day,
                value: -daysBefore,
                to: now
            )!
        )

        // Anchored to now, not to start — otherwise the
        // window would end today instead of N days ahead.
        let end = Calendar.current.date(
            byAdding: .day,
            value: daysAfter,
            to: now
        )!

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )

        return eventStore.events(matching: predicate)
            .map { CalendarEvent(event: $0) }
    }

}
