//
//  Reminder.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation

struct ReminderContext {

    let currentDate: Date

    let currentLocation: String

    let upcomingEvents: [String]

    let pendingReminders: [String]

    let frequentLocations: [String]

    let recentReminderHistory: [String]

    let answeredQuestions: [String]

}

//let session = LanguageModelSession()
//
//let response = try await session.respond(to: <#T##Prompt#>)
