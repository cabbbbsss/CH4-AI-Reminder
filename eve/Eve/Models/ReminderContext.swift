//
//  ReminderContext.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation

/// The single object the Foundation Model is allowed to see.
/// Built by ReminderContextBuilder; the model never touches
/// EventKit, Core Location, or SwiftData directly.
struct ReminderContext {

    let currentDate: Date

    let currentPlace: String?

    let upcomingEvents: [String]

    let pendingReminders: [String]

    let insights: [String]

    let recentHistory: [String]

    let answeredQuestions: [String]

    /// Renders the context as the prompt text sent to the model.
    var promptText: String {

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        return """
        Current date and time: \(currentDate.formatted(date: .complete, time: .shortened))
        Current place: \(currentPlace ?? "unknown")

        \(section("Upcoming calendar events", upcomingEvents))

        \(section("Pending reminders", pendingReminders))

        \(section("Current beliefs about the user (AI Insights)", insights))

        \(section("Recent activity history", recentHistory))

        \(section("Questions the user has answered", answeredQuestions))
        """

    }

}
