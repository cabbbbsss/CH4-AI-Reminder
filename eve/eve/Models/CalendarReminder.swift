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

    var createdAt: Date

    /// When this reminder should appear on the timeline: one hour before
    /// the event it's for.
    var reminderDate: Date {
        eventDate.addingTimeInterval(-3600)
    }

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
