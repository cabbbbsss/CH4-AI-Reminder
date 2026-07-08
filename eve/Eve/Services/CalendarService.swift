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

    init() {
        self.eventStore = EKEventStore()
    }

    func requestAccess() async throws {
        try await eventStore.requestFullAccessToEvents()
        
    }
    
    func fetchTodayEvents() -> [CalendarEvent] {
        
        let calendars = eventStore.calendars(for: .event)
        
        let start = Calendar.current.startOfDay(for: Date())
        
        let end = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: start
        )!
        
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        
        return eventStore.events(matching: predicate)
            .map{
                CalendarEvent(
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            }
    }
    
    func requestReminderAccess() async throws {
        try await eventStore.requestFullAccessToReminders()
    }
    
    func fetchIncompleteReminders() async -> [ReminderItem] {

        await withCheckedContinuation { continuation in

            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )

            eventStore.fetchReminders(
                matching: predicate
            ) { reminders in

                let items = reminders?.map {

                    ReminderItem(

                        title: $0.title,

                        dueDate: $0.dueDateComponents?.date

                    )

                } ?? []

                continuation.resume(returning: items)

            }

        }

    }
}
