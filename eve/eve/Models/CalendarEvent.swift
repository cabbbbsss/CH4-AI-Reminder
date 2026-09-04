//
//  CalendarEvent.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData
import EventKit

@Model
final class CalendarEvent {

    /// Unique per occurrence. Recurring events share one eventIdentifier
    /// in EventKit, so the identifier alone would collapse every repeat
    /// of "Standup" into a single row.
    @Attribute(.unique) var occurrenceID: String

    var eventIdentifier: String

    var title: String

    var startDate: Date

    var endDate: Date

    /// The event's free-text notes (EKEvent.notes).
    ///
    /// Sent to the model by `ReminderContextBuilder.buildPreparationContext`
    /// — a prep checklist is only useful if it can see the agenda. This is the
    /// largest attacker-reachable span in the whole prompt (anyone who can send
    /// the user an invite writes it), so it is wrapped by `UntrustedText`
    /// before it reaches the model. It is *not* part of the wide
    /// `ReminderContext` used by `decide(from:)`.
    var notes: String?

    /// The event's location text, if any (EKEvent.location).
    ///
    /// Wrapped by `UntrustedText` before it reaches the model. Venue names are
    /// often non-English, so it passes through `englishOrNil` first — a
    /// non-English value is dropped rather than tripping the on-device model's
    /// language check.
    var location: String?

    /// Comma-separated display names of the event's guests (EKEvent.attendees).
    ///
    /// Like notes and location, this is attacker-reachable invite text, so it
    /// is wrapped by `UntrustedText` and filtered for language before the model
    /// sees it.
    var attendees: String?

    /// The event's meeting link (EKEvent.url) — where Calendar puts a Zoom /
    /// Teams / Meet URL. Signals an online meeting, which lets Eve personalise
    /// ("you usually have virtual calls on Fridays"). Attacker-reachable like
    /// the other invite fields, so it is wrapped by `UntrustedText`.
    var meetingURL: String?

    init(event: EKEvent) {

        let identifier = event.eventIdentifier ?? UUID().uuidString

        self.eventIdentifier = identifier
        self.occurrenceID = "\(identifier)|\(event.startDate.timeIntervalSince1970)"
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        // Some calendars deliver notes as HTML; store clean plain text so the
        // UI and the model both get readable content, not raw markup.
        self.notes = HTMLText.plainIfNeeded(event.notes)
        self.location = event.location
        self.attendees = Self.attendeeNames(from: event)
        self.meetingURL = event.url?.absoluteString
    }

    /// Display names of the event's guests, or nil when there are none.
    private static func attendeeNames(from event: EKEvent) -> String? {
        guard let attendees = event.attendees, !attendees.isEmpty else { return nil }
        let names = attendees.compactMap(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

}
