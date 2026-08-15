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
    /// Sent to the model alongside `notes` in `buildPreparationContext`, and
    /// wrapped by `UntrustedText` the same way. Venue names are often
    /// non-English, so it passes through `englishOrNil` first — a non-English
    /// value is dropped rather than tripping the on-device model's language
    /// check. Like `notes`, it is not part of the wide `ReminderContext`.
    var location: String?

    init(event: EKEvent) {

        let identifier = event.eventIdentifier ?? UUID().uuidString

        self.eventIdentifier = identifier
        self.occurrenceID = "\(identifier)|\(event.startDate.timeIntervalSince1970)"
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.notes = event.notes
        self.location = event.location

    }

}
