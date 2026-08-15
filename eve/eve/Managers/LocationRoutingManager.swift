//
//  LocationRoutingManager.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// Curates each saved location's reminders (Home, Office, and anything the
/// user has added) from the user's upcoming calendar events.
///
/// Every upcoming event is assigned to **at most one** place in a single
/// global pass (see `ReminderContextBuilder.matchedEventsByLocation`) — by
/// name/address text, the event's own location, or a time-of-day fallback
/// for Home/Work places — so the same event never generates reminders under
/// two different cards. Each assigned event then gets its own on-device
/// generation pass producing 1-2 short, concrete, activity-based reminders
/// (e.g. "Cook + Lunch" → "Make sure the ingredients are complete"),
/// prefixed with the event's title. Past events never generate reminders,
/// and a recurring event only produces one (its nearest upcoming
/// occurrence).
///
/// Only system-managed rows are (re)generated on each refresh; anything the
/// user added, edited, moved, or assigned is preserved untouched.
final class LocationRoutingManager {

    private let context: ModelContext

    private let contextBuilder: ReminderContextBuilder

    // No shared FoundationModelService: generation runs in a task group and
    // each task makes its own (see `items(for:index:)`).

    init(context: ModelContext) {
        self.context = context
        self.contextBuilder = ReminderContextBuilder(context: context)
    }

    /// Re-derives every location's system-managed reminders from the current
    /// calendar data via the on-device model. Safe to call repeatedly
    /// ("refresh"): user-owned rows (added, edited, moved, or manually
    /// assigned) are preserved; only untouched system rows are regenerated,
    /// so new events, addresses, or reminders get picked up.
    func seedReminders() async {

        let locations = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []
        guard !locations.isEmpty else { return }

        // Keys the user ticked off *today* — a completed reminder stays put
        // for the rest of the day and must not be regenerated, so refreshing
        // never resurfaces something they already handled this morning.
        let allBeforeWipe = (try? context.fetch(FetchDescriptor<LocationReminder>())) ?? []
        let completedTodayKeys = Set(
            allBeforeWipe
                .filter { $0.isCompleted && ($0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false) }
                .compactMap { $0.itemKey }
        )

        // 1. Wipe regenerable rows, keep everything the user touched — plus
        //    system rows completed today, which stay visible (checked) so the
        //    day's progress survives a refresh.
        for reminder in allBeforeWipe where reminder.isSystemManaged {
            let keepChecked = reminder.isCompleted
                && (reminder.completedAt.map { Calendar.current.isDateInToday($0) } ?? false)
            if !keepChecked {
                context.delete(reminder)
            }
        }

        // Survivors: text the user already owns — never regenerate these.
        let survivingReminders = (try? context.fetch(FetchDescriptor<LocationReminder>())) ?? []
        // Guard against reinserting anything the user owns or completed today.
        let ownedKeys = Set(survivingReminders.compactMap { $0.itemKey }).union(completedTodayKeys)

        // 2. Assign every upcoming event to at most one place, then ask the
        //    model for each place's event-derived reminders.
        let eventsByLocation = contextBuilder.matchedEventsByLocation(
            locations.map { (id: $0.id, name: $0.name, address: $0.address) }
        )

        let curatedByLocation = await curatedReminders(
            locations: locations,
            eventsByLocation: eventsByLocation
        )

        for location in locations {

            let curated = curatedByLocation[location.id] ?? []

            var seenInPlace = Set<String>()

            for (text, eventTitle) in curated {

                let key = normalize(text)
                guard !key.isEmpty,
                      !ownedKeys.contains(key),
                      !seenInPlace.contains(key) else { continue }
                seenInPlace.insert(key)

                context.insert(
                    LocationReminder(locationID: location.id, text: text, itemKey: key, eventTitle: eventTitle, isSystemManaged: true)
                )

            }

        }

        for location in locations where !location.hasBeenSeeded {
            location.hasBeenSeeded = true
        }

        try? context.save()

    }

    /// One event's generation for one place, reduced to plain values so it can
    /// cross into a task group. Nothing SwiftData-backed goes with it.
    private struct PlaceJob {
        let locationID: UUID
        let eventTitle: String
        let promptText: String
    }

    /// AI-curated, per-event reminders for every place at once — e.g. an
    /// upcoming "Cook + Lunch" event becomes "Make sure the ingredients are
    /// complete." One generation pass per already-matched event (see
    /// `seedReminders`). A place is absent from the result when it has no
    /// assigned events, an event's title isn't English-safe, or the model is
    /// unavailable — callers just show "nothing learned yet".
    ///
    /// This was a nested serial loop (places × up to six events each, one
    /// awaited model call per pair) behind the Locations screen's blocking
    /// spinner — comfortably tens of sequential round-trips on a populated
    /// account. Prompts are built here from SwiftData, the model calls run
    /// off-actor, and the caller does all the inserts.
    private func curatedReminders(
        locations: [SavedLocation],
        eventsByLocation: [UUID: [CalendarEvent]]
    ) async -> [UUID: [(text: String, eventTitle: String)]] {

        let jobs: [PlaceJob] = locations.flatMap { location in
            (eventsByLocation[location.id] ?? []).compactMap { event in

                // Only the prompt text is taken. This path runs
                // `suggestLocationReminder`, which is inferential by design —
                // "Gym" is *supposed* to yield workout gear with nothing in
                // the context saying so — so `OutputGrounding` is deliberately
                // not applied here. It would drop exactly the items this
                // feature exists to produce. See `suggestLocationReminder`.
                guard let prompt = contextBuilder.buildPreparationContext(
                    eventTitle: event.title,
                    eventDate: event.startDate,
                    eventNotes: event.notes,
                    eventLocation: event.location
                ) else { return nil }

                return PlaceJob(
                    locationID: location.id,
                    eventTitle: event.title,
                    promptText: prompt.promptText
                )

            }
        }

        guard !jobs.isEmpty else { return [:] }

        let itemsByJob = await Self.generate(jobs: jobs)

        // Regroup in job order, not completion order, so a place's reminders
        // stay in event order the way the serial version produced them — the
        // per-place `prefix(8)` below depends on that being stable.
        var curated: [UUID: [(text: String, eventTitle: String)]] = [:]

        for (index, job) in jobs.enumerated() {
            // The event is shown as the row's subtitle now, so store just the
            // suggestion as the reminder text — no "Title: " prefix.
            for text in itemsByJob[index] ?? [] {
                curated[job.locationID, default: []].append(
                    (text: text, eventTitle: job.eventTitle)
                )
            }
        }

        return curated.mapValues { Array($0.prefix(8)) }

    }

    /// Runs the per-event calls concurrently, at most `maxConcurrent` in
    /// flight, keyed by each job's index so ordering survives.
    ///
    /// Bounded for the same reason as `CalendarReminderManager`: the
    /// on-device model serialises internally, so an unbounded group over a
    /// populated account would hold dozens of live sessions to no benefit.
    private static func generate(
        jobs: [PlaceJob],
        maxConcurrent: Int = 4
    ) async -> [Int: [String]] {

        await withTaskGroup(of: (Int, [String]).self) { group in

            var results: [Int: [String]] = [:]
            var next = 0

            while next < min(maxConcurrent, jobs.count) {
                let index = next
                group.addTask { await Self.items(for: jobs[index], index: index) }
                next += 1
            }

            for await (index, items) in group {

                results[index] = items

                if next < jobs.count {
                    let queued = next
                    group.addTask { await Self.items(for: jobs[queued], index: queued) }
                    next += 1
                }

            }

            return results

        }

    }

    private static func items(for job: PlaceJob, index: Int) async -> (Int, [String]) {
        let service = FoundationModelService()
        let items = (try? await service.suggestLocationReminder(forPromptText: job.promptText)) ?? []
        return (index, items)
    }

    /// Reminders-app items that aren't shown under any location — surfaced
    /// in the Unsorted section for the user to assign.
    func unassignedReminderTitles() -> [String] {

        let shownKeys = Set(
            ((try? context.fetch(FetchDescriptor<LocationReminder>())) ?? [])
                .compactMap { $0.itemKey }
        )

        let reminderItems = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        var seen = Set<String>()
        var result: [String] = []

        for item in reminderItems {
            let key = normalize(item.title)
            guard !key.isEmpty, !shownKeys.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item.title)
        }

        return result

    }

    /// The user assigns an Unsorted reminder to a place. Creates a
    /// user-owned row (survives refresh) and remembers the choice.
    func assignUnsorted(title: String, to location: SavedLocation) {

        let key = normalize(title)

        context.insert(
            LocationReminder(locationID: location.id, text: title, itemKey: key, isSystemManaged: false)
        )

        upsertAssignment(key: key, locationID: location.id, userConfirmed: true)

        try? context.save()

    }

    /// Records the user moving/confirming a source event's place — a
    /// permanent override for every reminder generated from that event, not
    /// just the one edited. Moves every existing sibling reminder (rows
    /// sharing the same `eventTitle`) to the new place immediately, and
    /// persists the override so future refreshes keep assigning that event
    /// there too — otherwise a leftover strong/weak match elsewhere could
    /// scatter its reminders right back across cards on the next refresh.
    func confirmAssignment(itemTitle: String, location: SavedLocation) {

        let key = normalize(itemTitle)
        upsertAssignment(key: key, locationID: location.id, userConfirmed: true)

        let allReminders = (try? context.fetch(FetchDescriptor<LocationReminder>())) ?? []
        for reminder in allReminders where reminder.eventTitle.map(normalize) == key {
            reminder.locationID = location.id
            // Any user-driven move makes it theirs — refresh must not
            // regenerate it back onto whichever place it just left.
            reminder.isSystemManaged = false
        }

        try? context.save()

    }

    /// Ticks a reminder off (or un-ticks it). A completed row stays checked
    /// and, if system-sourced, is suppressed from AI regeneration for the
    /// rest of the day — see `seedReminders`.
    func toggleCompletion(_ reminder: LocationReminder) {

        reminder.isCompleted.toggle()
        reminder.completedAt = reminder.isCompleted ? .now : nil
        try? context.save()

    }

    /// Removes a reminder from its card. A system-sourced item drops back to
    /// Unsorted (we can't delete the underlying Reminders-app item); a
    /// freeform one is gone for good.
    func remove(_ reminder: LocationReminder) {

        if let key = reminder.itemKey {
            let assignments = (try? context.fetch(FetchDescriptor<LocationAssignment>())) ?? []
            for assignment in assignments where assignment.itemKey == key {
                context.delete(assignment)
            }
        }

        context.delete(reminder)
        try? context.save()

    }

    // MARK: - Helpers

    private func upsertAssignment(key: String, locationID: UUID, userConfirmed: Bool) {

        let descriptor = FetchDescriptor<LocationAssignment>(
            predicate: #Predicate { $0.itemKey == key }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.locationID = locationID
            existing.userConfirmed = userConfirmed
            existing.updatedAt = .now
        } else {
            context.insert(
                LocationAssignment(itemKey: key, locationID: locationID, userConfirmed: userConfirmed)
            )
        }

    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
