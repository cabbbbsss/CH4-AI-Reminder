//
//  ReminderItem.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData
import EventKit

@Model
final class ReminderItem {

    @Attribute(.unique) var reminderIdentifier: String

    var title: String

    var dueDate: Date?

    var notes: String?

    init(reminder: EKReminder) {

        self.reminderIdentifier = reminder.calendarItemIdentifier
        self.title = reminder.title
        self.dueDate = reminder.dueDateComponents?.date
        self.notes = reminder.notes

    }

}
