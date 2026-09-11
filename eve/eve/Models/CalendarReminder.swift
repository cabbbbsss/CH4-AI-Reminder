//
//  CalendarReminder.swift
//  Eve
//
//  Created by cabsss on 09/07/26.
//

import Foundation
import SwiftData

/// An AI-generated (or user-edited) reminder tied to one calendar event
/// occurrence, shown on the Calendar timeline one hour before the event
/// itself — not at the same time as the event.
///
/// Mirrors LocationReminder's ownership model: system-managed rows are
/// wiped and regenerated on reload; anything the user edits or adds is
/// preserved untouched.
@Model
final class CalendarReminder {

    var id: UUID

    /// Matches CalendarEvent.occurrenceID — the specific event occurrence
    /// this reminder was generated from.
    var occurrenceID: String

    var eventTitle: String

    /// The source event's own start time (not this reminder's shown time —
    /// see `reminderDate`).
    var eventDate: Date

    var text: String

    var isSystemManaged: Bool

    /// Ticked off in Today's Routine.
    var isCompleted: Bool = false

    var createdAt: Date

    // MARK: - User-editable detail

    /// The second line on the routine row, and the body of its notification.
    var notes: String?

    /// A link the reminder is about. Display-only.
    var url: String?

    /// The time the user set, which overrides the generated one.
    ///
    /// Optional rather than a plain stored date so existing rows keep working:
    /// `reminderDate` still derives from the event when nobody has edited it,
    /// which is exactly the old behaviour and needs no migration.
    var scheduledDate: Date?

    /// False for an all-day reminder — it still has a date, just no clock time.
    var hasTime: Bool = true

    /// The `SavedLocation` this reminder is tied to, if any. Reaching or
    /// leaving there delivers it (see `LocationActivityManager`).
    var locationID: UUID?

    /// Which half of the visit delivers it. Only meaningful with a location.
    var locationTriggerRaw: String = LocationTrigger.arriving.rawValue

    var locationTrigger: LocationTrigger {
        get { LocationTrigger(rawValue: locationTriggerRaw) ?? .arriving }
        set { locationTriggerRaw = newValue.rawValue }
    }

    /// `RepeatRule.rawValue`. Stored raw because SwiftData persists primitives.
    var repeatRuleRaw: String = RepeatRule.never.rawValue

    /// Minutes before `reminderDate` that the notification fires.
    var earlyReminderMinutes: Int = 0

    /// Groups every instance of one repeating series, so the next occurrence
    /// can tell whether it has already been created.
    var seriesID: UUID?

    // MARK: - Derived

    /// When this reminder appears on the timeline.
    ///
    /// The user's own time wins; otherwise it falls back to an hour before the
    /// event it was generated from.
    var reminderDate: Date {
        scheduledDate ?? eventDate.addingTimeInterval(-3600)
    }

    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .never }
        set { repeatRuleRaw = newValue.rawValue }
    }

    var earlyReminder: EarlyReminder {
        get { EarlyReminder(rawValue: earlyReminderMinutes) ?? .none }
        set { earlyReminderMinutes = newValue.rawValue }
    }

    /// When the notification should actually be delivered.
    var fireDate: Date {
        reminderDate.addingTimeInterval(-Double(earlyReminderMinutes) * 60)
    }

    /// Stable identifier for this reminder's pending notification, so it can
    /// be cancelled and replaced whenever the reminder is edited.
    var notificationID: String { "calendar-reminder-\(id.uuidString)" }

    init(
        occurrenceID: String,
        eventTitle: String,
        eventDate: Date,
        text: String,
        isSystemManaged: Bool = true,
        createdAt: Date = .now
    ) {

        self.id = UUID()
        self.occurrenceID = occurrenceID
        self.eventTitle = eventTitle
        self.eventDate = eventDate
        self.text = text
        self.isSystemManaged = isSystemManaged
        self.createdAt = createdAt

    }

}
