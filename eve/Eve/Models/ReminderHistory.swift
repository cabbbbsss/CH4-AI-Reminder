//
//  ReminderHistory.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData

@Model
final class ReminderHistory {

    var title: String

    var action: ReminderAction

    var date: Date

    init(
        title: String,
        action: ReminderAction,
        date: Date = .now
    ) {

        self.title = title
        self.action = action
        self.date = date

    }

}
