//
//  ReminderScheduler.swift
//  Eve
//

import Foundation
import SwiftData

/// Delivers `CalendarReminder`s: schedules their notifications, keeps those in
/// step with edits, and grows a repeating series one instance at a time.
///
/// Before this, these reminders were only ever *displayed* — nothing scheduled
/// them, so a reminder with a time never actually announced itself. Every path
/// that changes a reminder now runs through here, because a stale pending
/// notification is worse than none: it fires for a time the user has since
/// changed.
/// Not actor-isolated, matching `CalendarReminderManager` and
/// `LocationRoutingManager`: these managers are created with a `ModelContext`
/// and driven from both views and the location stream.
final class ReminderScheduler {

    private let context: ModelContext
    private let notifications: NotificationService

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest, so a full resync schedules only the soonest ones. The
    /// remainder are picked up by the next resync, which happens on every
    /// launch and after every edit.
    private static let pendingLimit = 60

    init(context: ModelContext, notifications: NotificationService = .shared) {
        self.context = context
        self.notifications = notifications
    }

    // MARK: - One reminder

    /// Cancels whatever was pending for this reminder and schedules it afresh.
    ///
    /// Safe to call after any edit, including ones that should leave nothing
    /// pending — a completed, undated or past reminder simply ends up cancelled.
    /// - Parameter mayPrompt: passed to `NotificationService`. True when the
    ///   user just edited this reminder, false for a bulk resync.
    func sync(_ reminder: CalendarReminder, mayPrompt: Bool = true) async {

        notifications.cancelReminder(id: reminder.notificationID)

        guard !reminder.isCompleted else { return }

        // A location-triggered reminder is delivered on arrival instead of on
        // a clock (see `deliverOnArrival`), so it gets no timed notification.
        guard reminder.locationID == nil else { return }

        let fireDate = reminder.fireDate
        guard fireDate > .now else { return }

        try? await notifications.scheduleReminder(
            id: reminder.notificationID,
            title: reminder.text,
            body: reminder.notes ?? reminder.eventTitle,
            at: fireDate,
            mayPrompt: mayPrompt
        )
    }

    func cancel(_ reminder: CalendarReminder) {
        notifications.cancelReminder(id: reminder.notificationID)
    }

    // MARK: - Everything

    /// Rebuilds the pending set from the store. Call on launch, after which
    /// per-reminder `sync` keeps it current.
    ///
    /// Never prompts: this runs at startup over reminders that already exist,
    /// and a permission dialog here would block whatever is queued behind it.
    /// Permission is asked for when the user saves or completes a reminder.
    func syncAll() async {

        let all = (try? context.fetch(FetchDescriptor<CalendarReminder>())) ?? []

        let upcoming = all
            .filter { !$0.isCompleted && $0.locationID == nil && $0.fireDate > .now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.pendingLimit)

        for reminder in upcoming {
            await sync(reminder, mayPrompt: false)
        }
    }

    // MARK: - Completion + recurrence

    /// Ticks a reminder off and, when it repeats, puts the next one on the
    /// calendar.
    ///
    /// Instances are created on completion rather than expanded ahead of time,
    /// so a daily reminder never accumulates a year of unread rows. Un-ticking
    /// only reinstates the notification — it deliberately does not delete the
    /// next instance, which the user may already have edited.
    func setCompleted(_ reminder: CalendarReminder, _ completed: Bool) async {

        reminder.isCompleted = completed

        if completed {
            await advanceSeries(from: reminder)
        }

        try? context.save()
        await sync(reminder)
    }

    /// Creates the next occurrence of a repeating reminder, if there isn't one.
    private func advanceSeries(from reminder: CalendarReminder) async {

        let rule = reminder.repeatRule
        guard rule != .never else { return }
        guard let nextDate = rule.nextDate(after: reminder.reminderDate) else { return }

        // Every instance of a series shares this. Back-fill it for reminders
        // created before repeats existed, so the first completion still links.
        let series = reminder.seriesID ?? reminder.id
        reminder.seriesID = series

        // Completing the same reminder twice, or completing an older instance
        // after a newer one already exists, must not fork the series.
        let existing = (try? context.fetch(FetchDescriptor<CalendarReminder>())) ?? []
        let alreadyThere = existing.contains { candidate in
            candidate.seriesID == series
                && candidate.id != reminder.id
                && Calendar.current.isDate(candidate.reminderDate, inSameDayAs: nextDate)
        }
        guard !alreadyThere else { return }

        let next = CalendarReminder(
            occurrenceID: reminder.occurrenceID,
            eventTitle: reminder.eventTitle,
            eventDate: reminder.eventDate,
            text: reminder.text,
            isSystemManaged: false
        )

        next.notes = reminder.notes
        next.url = reminder.url
        next.scheduledDate = nextDate
        next.hasTime = reminder.hasTime
        next.locationID = reminder.locationID
        next.repeatRuleRaw = reminder.repeatRuleRaw
        next.earlyReminderMinutes = reminder.earlyReminderMinutes
        next.seriesID = series

        context.insert(next)
        try? context.save()

        await sync(next)
    }

    // MARK: - Location delivery

    /// Delivers everything pinned to a place the user has just reached or just
    /// left.
    ///
    /// Called from `LocationActivityManager` when the current place changes,
    /// once for the place being left and once for the one being reached.
    /// Matching is by distance to the saved coordinate rather than by place
    /// name, because the reverse-geocoded name of a coordinate is not stable
    /// enough to compare against a name the user typed themselves.
    func deliver(
        trigger: LocationTrigger,
        near latitude: Double,
        longitude: Double,
        radius: Double = 150
    ) async {

        let places = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []

        let matches = places.filter { place in
            guard let lat = place.latitude, let lon = place.longitude else { return false }
            return Self.metres(from: (latitude, longitude), to: (lat, lon)) <= radius
        }

        guard let place = matches.first else { return }
        let ids = Set(matches.map(\.id))

        // Reminders Eve generated for the day, pinned to this place.
        let calendarReminders = (try? context.fetch(FetchDescriptor<CalendarReminder>())) ?? []

        for reminder in calendarReminders
        where !reminder.isCompleted
            && reminder.locationTrigger == trigger
            && reminder.locationID.map(ids.contains) == true {

            await post(
                id: reminder.notificationID,
                title: reminder.text,
                body: reminder.notes ?? "\(trigger.title) \(place.name)"
            )
        }

        // The place's own list, from the Locations tab.
        let locationReminders = (try? context.fetch(FetchDescriptor<LocationReminder>())) ?? []

        for reminder in locationReminders
        where !reminder.isCompleted
            && reminder.trigger == trigger
            && ids.contains(reminder.locationID)
            && !Self.hasLapsed(reminder) {

            await post(
                id: "location-reminder-\(reminder.id.uuidString)",
                title: reminder.text,
                body: "\(trigger.title) \(place.name)"
            )
        }
    }

    /// A dated reminder stops applying once its day is over — otherwise "buy
    /// milk on Tuesday" keeps firing every time the user passes the shop.
    private static func hasLapsed(_ reminder: LocationReminder) -> Bool {
        guard let due = reminder.dueDate else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: .now)
    }

    /// nil `at` delivers almost immediately. Never prompts: arrival can happen
    /// with the app in the background, where a prompt cannot be shown at all.
    private func post(id: String, title: String, body: String) async {
        try? await notifications.scheduleReminder(
            id: id,
            title: title,
            body: body,
            at: nil,
            mayPrompt: false
        )
    }

    /// Great-circle distance in metres. Enough for a "have we arrived" test,
    /// and avoids pulling CoreLocation into this type just for one call.
    private static func metres(
        from origin: (Double, Double),
        to destination: (Double, Double)
    ) -> Double {

        let earthRadius = 6_371_000.0
        let lat1 = origin.0 * .pi / 180
        let lat2 = destination.0 * .pi / 180
        let deltaLat = (destination.0 - origin.0) * .pi / 180
        let deltaLon = (destination.1 - origin.1) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)

        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
