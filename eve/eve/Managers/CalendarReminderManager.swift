//
//  CalendarReminderManager.swift
//  Eve
//
//  Created by cabsss on 09/07/26.
//

import Foundation
import SwiftData

/// Curates the Calendar screen's per-event reminders: for every calendar
/// event on a given day, generates 1-2 short prep items via the on-device
/// model (see `ReminderContextBuilder.buildPreparationContext`), shown one
/// hour before the event.
///
/// Only system-managed rows are (re)generated — once an event has any
/// reminder at all (system or user-edited), it's left alone until every
/// reminder for it is removed. Mirrors LocationRoutingManager's
/// wipe-and-regen pattern.
final class CalendarReminderManager {

    private let context: ModelContext

    private let contextBuilder: ReminderContextBuilder

    private let foundationModel = FoundationModelService()

    init(context: ModelContext) {
        self.context = context
        self.contextBuilder = ReminderContextBuilder(context: context)
    }

    /// Generates reminders for any event on `date` that doesn't have one
    /// yet. Safe to call repeatedly — existing rows (system or user-owned)
    /// are never duplicated.
    func ensureReminders(for date: Date) async {

        let events = eventsOn(date)
        guard !events.isEmpty else { return }

        let coveredOccurrenceIDs = Set(existingReminders(for: date).map(\.occurrenceID))

        for event in events where !coveredOccurrenceIDs.contains(event.occurrenceID) {
            await generate(for: event)
        }

        try? context.save()

    }

    /// Reload: wipes system-managed reminders for `date`, then regenerates
    /// for any event left without a reminder. Events with a user-edited row
    /// keep it and are not touched.
    func regenerate(for date: Date) async {

        for reminder in existingReminders(for: date) where reminder.isSystemManaged {
            context.delete(reminder)
        }

        try? context.save()

        await ensureReminders(for: date)

    }

    func remove(_ reminder: CalendarReminder) {
        context.delete(reminder)
        try? context.save()
    }

    // MARK: - Generation

    private func generate(for event: CalendarEvent) async {

        guard let promptText = contextBuilder.buildPreparationContext(
            eventTitle: event.title,
            eventDate: event.startDate,
            eventNotes: event.notes,
            eventLocation: event.location
        ) else { return }

        let items = (try? await foundationModel.suggestPreparation(forPromptText: promptText)) ?? []

        for text in items.prefix(4) {
            context.insert(
                CalendarReminder(
                    occurrenceID: event.occurrenceID,
                    eventTitle: event.title,
                    eventDate: event.startDate,
                    text: text,
                    isSystemManaged: true
                )
            )
        }

    }

    // MARK: - Fetching

    private func eventsOn(_ date: Date) -> [CalendarEvent] {

        let descriptor = FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.startDate)])
        let all = (try? context.fetch(descriptor)) ?? []

        return all.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }

    }

    private func existingReminders(for date: Date) -> [CalendarReminder] {

        let all = (try? context.fetch(FetchDescriptor<CalendarReminder>())) ?? []

        return all.filter { Calendar.current.isDate($0.eventDate, inSameDayAs: date) }

    }

}
