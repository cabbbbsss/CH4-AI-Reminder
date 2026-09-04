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

    // No shared FoundationModelService: generation runs in a task group and
    // each task makes its own (see `prepItems(for:)`).

    init(context: ModelContext) {
        self.context = context
        self.contextBuilder = ReminderContextBuilder(context: context)
    }

    /// One event's prep generation, reduced to plain values so it can cross
    /// into a task group. Nothing SwiftData-backed goes with it.
    private struct PrepJob {
        let occurrenceID: String
        let eventTitle: String
        let eventDate: Date
        let promptText: String

        /// Carried alongside the prompt so the grounding check can run inside
        /// the task group, on the same values the prompt was built from.
        let groundingTerms: Set<String>

        /// Title-only terms, so an item that just restates the event name
        /// ("Bring breakfast" for "Breakfast") can be discarded.
        let subjectTerms: Set<String>
    }

    /// Generates reminders for any event on `date` that doesn't have one
    /// yet. Safe to call repeatedly — existing rows (system or user-owned)
    /// are never duplicated.
    func ensureReminders(for date: Date) async {

        let events = eventsOn(date)
        guard !events.isEmpty else { return }

        let coveredOccurrenceIDs = Set(existingReminders(for: date).map(\.occurrenceID))

        // Three phases, deliberately: read SwiftData and build every prompt
        // here, run the model calls off-actor, then insert back here. The
        // ModelContext never crosses a task boundary.
        //
        // This used to await one model call per event in series behind the
        // Calendar screen's blocking spinner, and `.task(id: selectedDate)`
        // re-runs it on *every* date change — so an eight-event day cost
        // eight sequential round-trips before anything appeared.
        let jobs: [PrepJob] = events
            .filter { !coveredOccurrenceIDs.contains($0.occurrenceID) }
            .compactMap { event in

                guard let prompt = contextBuilder.buildPreparationContext(
                    eventTitle: event.title,
                    eventDate: event.startDate,
                    eventNotes: event.notes,
                    eventLocation: event.location,
                    eventAttendees: event.attendees,
                    eventMeetingURL: event.meetingURL
                ) else { return nil }

                return PrepJob(
                    occurrenceID: event.occurrenceID,
                    eventTitle: event.title,
                    eventDate: event.startDate,
                    promptText: prompt.promptText,
                    groundingTerms: prompt.groundingTerms,
                    subjectTerms: prompt.subjectTerms
                )

            }

        guard !jobs.isEmpty else { return }

        let itemsByOccurrence = await Self.generatePrep(for: jobs)

        for job in jobs {
            for text in (itemsByOccurrence[job.occurrenceID] ?? []).prefix(4) {
                context.insert(
                    CalendarReminder(
                        occurrenceID: job.occurrenceID,
                        eventTitle: job.eventTitle,
                        eventDate: job.eventDate,
                        text: text,
                        isSystemManaged: true
                    )
                )
            }
        }

        try? context.save()

    }

    /// Runs the prep calls concurrently, at most `maxConcurrent` in flight.
    ///
    /// The cap is deliberate. The on-device model serialises requests
    /// internally, so an unbounded group mostly just queues them — while
    /// still holding one live `LanguageModelSession` per event. Four keeps
    /// the screen responsive on a heavy day without piling sessions up.
    ///
    /// Each task builds its own `FoundationModelService`; the type holds only
    /// instruction strings, so this is cheap and keeps anything non-Sendable
    /// from being captured across the boundary.
    private static func generatePrep(
        for jobs: [PrepJob],
        maxConcurrent: Int = 4
    ) async -> [String: [String]] {

        await withTaskGroup(of: (String, [String]).self) { group in

            var results: [String: [String]] = [:]
            var next = 0

            while next < min(maxConcurrent, jobs.count) {
                let job = jobs[next]
                group.addTask { await Self.prepItems(for: job) }
                next += 1
            }

            for await (occurrenceID, items) in group {

                results[occurrenceID] = items

                if next < jobs.count {
                    let job = jobs[next]
                    group.addTask { await Self.prepItems(for: job) }
                    next += 1
                }

            }

            return results

        }

    }

    private static func prepItems(for job: PrepJob) async -> (String, [String]) {

        let service = FoundationModelService()

        let items = (try? await service.suggestPreparation(forPromptText: job.promptText)) ?? []

        // Gated here rather than at the insert below, so a dropped item never
        // becomes a `CalendarReminder` row — these persist and are shown as
        // Eve's own suggestions.
        let grounded = OutputGrounding.filterLogging(
            items,
            groundedIn: job.groundingTerms,
            notRestating: job.subjectTerms,
            label: "prep/\(job.eventTitle)"
        )

        return (job.occurrenceID, grounded)

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
