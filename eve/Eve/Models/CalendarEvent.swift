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

    var notes: String?

    init(event: EKEvent) {

        let identifier = event.eventIdentifier ?? UUID().uuidString

        self.eventIdentifier = identifier
        self.occurrenceID = "\(identifier)|\(event.startDate.timeIntervalSince1970)"
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.notes = event.notes

    }

}
