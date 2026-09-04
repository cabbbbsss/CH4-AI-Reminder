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

    /// What the user likes to be called. Lets the model occasionally
    /// address them by name in a reminder. nil/empty when unset.
    let userName: String?

    /// The single most time-urgent upcoming calendar event or dated
    /// reminder, found by escalating the search window hour by hour
    /// (next hour, then the hour after, ...) up to 24 hours out. nil when
    /// nothing falls within that horizon — the model should stay quiet
    /// rather than nudge about something far away.
    let nextUrgentItem: String?

    let meetingLink: String?
    let eventDescription: String?
    let eventLocation: String?
    let guests: [String]?

    let upcomingEvents: [String]

    let pendingReminders: [String]

    let insights: [String]

    let recentHistory: [String]

    let answeredQuestions: [String]

    /// Content words drawn from everything this context puts in front of the
    /// model, so its output can be held to the same material.
    ///
    /// Built from the fields rather than from `promptText`, which by then has
    /// section headers and `<untrusted>` tags mixed into the content — those
    /// would ground a proposed belief on the word "untrusted".
    ///
    /// `currentDate` is left out deliberately: every generated sentence tends
    /// to carry a weekday or month, so including it would ground almost
    /// anything on the calendar date alone.
    var groundingTerms: Set<String> {

        var terms = Set<String>()

        for text in [currentPlace, userName, nextUrgentItem, meetingLink, eventDescription, eventLocation].compactMap({ $0 }) {
            terms.formUnion(OutputGrounding.contentTerms(of: UntrustedText.strip(text)))
        }

        let allStringLists = upcomingEvents + pendingReminders + insights + recentHistory + answeredQuestions + (guests ?? [])
        for line in allStringLists {
            terms.formUnion(OutputGrounding.contentTerms(of: UntrustedText.strip(line)))
        }

        return terms

    }

    /// Renders the context as the prompt text sent to the model.
    var promptText: String {

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        return """
        Current date and time: \(currentDate.formatted(date: .complete, time: .shortened))
        Current place: \(currentPlace ?? "unknown")
        User's name: \((userName?.isEmpty == false ? userName : nil) ?? "unknown")

        Most urgent upcoming commitment: \(nextUrgentItem ?? "none within the next 24 hours")
        Meeting link: \(meetingLink ?? "none")
        Event location: \(eventLocation ?? "none")
        Event description: \(eventDescription ?? "none")
        \(section("Guests", guests ?? []))

        \(section("Upcoming calendar events", upcomingEvents))

        \(section("Pending reminders", pendingReminders))

        \(section("Current beliefs about the user (AI Insights)", insights))

        \(section("Recent activity history", recentHistory))

        \(section("Questions the user has answered", answeredQuestions))
        """

    }

}
