//
//  ReminderContextBuilder.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData
import NaturalLanguage

/// The only component allowed to gather information for the AI.
/// Reads the SwiftData mirror (kept fresh by EventKitSyncManager)
/// plus insights, history and answers, and condenses everything
/// into one ReminderContext.
final class ReminderContextBuilder {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func build(currentPlace: String?) -> ReminderContext {

        ReminderContext(
            currentDate: .now,
            currentPlace: currentPlace.flatMap(englishOrNil),
            nextUrgentItem: nextUrgentItem(),
            upcomingEvents: upcomingEvents(),
            pendingReminders: pendingReminders(),
            insights: insights(),
            recentHistory: recentHistory(),
            answeredQuestions: answeredQuestions()
        )

    }

    /// A deliberately narrow context for one event's prep checklist.
    ///
    /// Unlike `build(currentPlace:)`, this does NOT include the day's full
    /// list of other calendar events, and reminders/insights are filtered
    /// to ones that share a keyword with the event — not just handed over
    /// wholesale with an instruction to "only use if related." The model
    /// doesn't reliably self-filter irrelevant items from a list it's
    /// shown (confirmed: it surfaced an unrelated reminder for one event
    /// even after the calendar list alone was removed), so the filtering
    /// has to happen here, before anything reaches the prompt.
    func buildPreparationContext(
        eventTitle: String,
        eventDate: Date,
        eventNotes: String?,
        eventLocation: String?
    ) -> String? {

        // The event title is the prompt's subject and can't be filtered
        // out. If it's non-English, the on-device model rejects the whole
        // prompt ("Unsupported language id detected"), so skip the call
        // entirely — the caller shows "nothing specific" instead.
        guard isEnglishSafe(eventTitle) else { return nil }

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        var eventLine = "\(eventTitle) — \(eventDate.formatted(date: .omitted, time: .shortened))"

        if let eventLocation, let safeLocation = englishOrNil(eventLocation) {
            eventLine += "\nLocation: \(safeLocation)"
        }

        if let eventNotes, let safeNotes = englishOrNil(eventNotes) {
            eventLine += "\nEvent notes: \(safeNotes)"
        }

        let eventKeywords = keywords(from: "\(eventTitle) \(eventNotes ?? "")")

        return """
        Event: \(eventLine)

        \(section("Reminders that specifically match this event", relevantReminders(to: eventKeywords)))

        \(section("Beliefs about the user that specifically match this event", relevantInsights(to: eventKeywords)))
        """

    }

    /// A place-scoped context for the Locations screen's AI-curated
    /// reminders. Same principle as `buildPreparationContext`: calendar
    /// events, reminders, and beliefs are filtered to ones that share a
    /// keyword with the place name (or have it as their explicit
    /// location) before anything reaches the prompt — never handed over
    /// wholesale for the model to self-filter.
    func buildPlaceContext(placeName: String) -> String? {

        // The place name is the prompt's subject and can't be filtered out.
        // Reverse-geocoded names are often non-English (e.g. "Kabupaten
        // Badung") even with an en_US locale, since that only affects
        // street *types*, not proper nouns. A non-English subject makes the
        // on-device model reject the whole prompt, so skip the call and let
        // the caller show "nothing learned yet".
        guard isEnglishSafe(placeName) else { return nil }

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        let placeKeywords = keywords(from: placeName)
        let visits = visitCount(for: placeName)

        let visitLine = visits > 0
            ? "Visited \(visits) time\(visits == 1 ? "" : "s")"
            : "Not yet visited"

        return """
        Place: \(placeName)
        \(visitLine)

        \(section("Calendar events at or about this place", placeRelatedEvents(placeName: placeName, keywords: placeKeywords)))

        \(section("Reminders at or about this place", placeRelatedReminders(placeName: placeName, keywords: placeKeywords)))

        \(section("Beliefs about the user that specifically match this place", relevantInsights(to: placeKeywords)))
        """

    }

    private func visitCount(for placeName: String) -> Int {

        let items = (try? context.fetch(FetchDescriptor<HistoryItem>())) ?? []
        let prefix = "Arrived near "

        let matching = items.filter { item in
            guard item.type == .locationVisited else { return false }
            let name = item.title.hasPrefix(prefix) ? String(item.title.dropFirst(prefix.count)) : item.title
            return name.caseInsensitiveCompare(placeName) == .orderedSame
        }

        return matching.count

    }

    private func placeRelatedEvents(placeName: String, keywords placeKeywords: Set<String>, limit: Int = 10) -> [String] {

        let allEvents = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []

        let matching = allEvents.filter { event in
            let locationMatches = event.location.map { location in
                location.caseInsensitiveCompare(placeName) == .orderedSame
                    || sharesKeyword(location, with: placeKeywords)
            } ?? false
            let titleMatches = sharesKeyword(event.title, with: placeKeywords)
            return locationMatches || titleMatches
        }

        let sorted = matching.sorted { first, second in first.startDate < second.startDate }

        let lines: [String] = sorted.prefix(limit).map { event in
            "\(event.title) — \(event.startDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return englishOnly(lines)

    }

    private func placeRelatedReminders(placeName: String, keywords placeKeywords: Set<String>, limit: Int = 10) -> [String] {

        let allReminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        let matching = allReminders.filter { reminder in
            let locationMatches = reminder.location.map { location in
                location.caseInsensitiveCompare(placeName) == .orderedSame
                    || sharesKeyword(location, with: placeKeywords)
            } ?? false
            let titleMatches = sharesKeyword(reminder.title, with: placeKeywords)
            let notesMatch = reminder.notes.map { sharesKeyword($0, with: placeKeywords) } ?? false
            return locationMatches || titleMatches || notesMatch
        }

        let sorted = matching.sorted { first, second in
            (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }

        let lines: [String] = sorted.prefix(limit).map { reminder in
            guard let dueDate = reminder.dueDate else {
                return "\(reminder.title) — no due date"
            }
            return "\(reminder.title) — due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return englishOnly(lines)

    }

    /// Prompt for the Locations screen's item→place classifier. Given the
    /// user's saved places, prior user-confirmed assignments (as few-shot
    /// examples), and a batch of new item titles, asks the model which
    /// place each item belongs to (or none).
    ///
    /// Items whose title isn't English-safe are dropped before reaching
    /// the model — same reasoning as the other build* methods: a
    /// non-English subject makes the model reject the whole prompt.
    func buildClassificationContext(
        locations: [(name: String, address: String?)],
        items: [String],
        priorCorrections: [(item: String, locationName: String)]
    ) -> String? {

        let safeItems = items.filter { isEnglishSafe($0) }
        guard !safeItems.isEmpty, !locations.isEmpty else { return nil }

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        let locationLines = locations.map { location -> String in
            guard let address = location.address, isEnglishSafe(address) else {
                return location.name
            }
            return "\(location.name) — \(address)"
        }

        let correctionLines = priorCorrections.map { correction in
            "\(correction.item) → \(correction.locationName) (confirmed by user)"
        }

        let itemLines = safeItems.map { "- \($0)" }

        return """
        \(section("Saved places", locationLines))

        \(section("Previously confirmed assignments", correctionLines))

        Items to classify:
        \(itemLines.joined(separator: "\n"))
        """

    }

    // MARK: - Keyword relevance
    //
    // Prevents unrelated reminders/insights from ever reaching the prompt
    // for a given event, rather than trusting the model to ignore them.

    private static let stopwords: Set<String> = [
        "a", "an", "the", "at", "in", "on", "for", "to", "of", "and", "with",
        "is", "are", "this", "that", "your", "you", "me", "my", "it", "be",
        "do", "not", "no", "yes", "today", "tomorrow", "day", "time"
    ]

    private func keywords(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !Self.stopwords.contains($0) }
        return Set(words)
    }

    private func sharesKeyword(_ text: String, with eventKeywords: Set<String>) -> Bool {
        guard !eventKeywords.isEmpty else { return false }
        return !keywords(from: text).isDisjoint(with: eventKeywords)
    }

    private func relevantReminders(to eventKeywords: Set<String>, limit: Int = 10) -> [String] {

        let allReminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        let matching = allReminders.filter { reminder in
            let titleMatches = sharesKeyword(reminder.title, with: eventKeywords)
            let notesMatch = reminder.notes.map { sharesKeyword($0, with: eventKeywords) } ?? false
            return titleMatches || notesMatch
        }

        let sorted = matching.sorted { first, second in
            (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }

        let lines: [String] = sorted.prefix(limit).map { reminder in
            guard let dueDate = reminder.dueDate else {
                return "\(reminder.title) — no due date"
            }
            return "\(reminder.title) — due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return englishOnly(lines)

    }

    private func relevantInsights(to eventKeywords: Set<String>) -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let allInsights = (try? context.fetch(descriptor)) ?? []

        let matching = allInsights.filter { insight in
            sharesKeyword(insight.title, with: eventKeywords)
                || sharesKeyword(insight.value, with: eventKeywords)
        }

        return englishOnly(matching.map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return "[\(insight.category.rawValue)] \(insight.title): \(insight.value) (\(origin))"

        })

    }

    // MARK: - Urgency

    /// True if there's anything pending at all — any future calendar event,
    /// or any reminder (due or not). Used to decide whether it's even worth
    /// asking the model, versus showing a deterministic "day's clear" state.
    func hasAnyPendingCommitment() -> Bool {

        let now = Date.now

        var eventDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now }
        )
        eventDescriptor.fetchLimit = 1

        let eventCount = (try? context.fetchCount(eventDescriptor)) ?? 0

        if eventCount > 0 {
            return true
        }

        var reminderDescriptor = FetchDescriptor<ReminderItem>()
        reminderDescriptor.fetchLimit = 1

        return ((try? context.fetchCount(reminderDescriptor)) ?? 0) > 0

    }

    /// Finds the single most time-urgent upcoming commitment (calendar event
    /// or dated reminder), escalating the search window hour by hour — next
    /// hour, then the hour after, and so on — up to a 24-hour horizon.
    /// Beyond that, nothing is "urgent" enough to lead with yet.
    private func nextUrgentItem() -> String? {

        let now = Date.now

        var eventDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now },
            sortBy: [SortDescriptor(\.startDate)]
        )
        eventDescriptor.fetchLimit = 20

        let events = (try? context.fetch(eventDescriptor)) ?? []

        let allReminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        var upcoming: [(title: String, date: Date)] = events.map { ($0.title, $0.startDate) }

        upcoming.append(contentsOf: allReminders.compactMap { reminder in
            guard let due = reminder.dueDate, due >= now else { return nil }
            return (reminder.title, due)
        })

        let horizon: TimeInterval = 24 * 3600

        let withinHorizon = upcoming.filter { item in item.date.timeIntervalSince(now) <= horizon }
        let sorted = withinHorizon.sorted { first, second in first.date < second.date }

        guard let nearest = sorted.first else {
            return nil
        }

        let hoursAway = max(1, Int(ceil(nearest.date.timeIntervalSince(now) / 3600)))
        let urgency = hoursAway <= 1 ? "within the next hour" : "in about \(hoursAway) hours"

        return englishOrNil(
            "\(nearest.title) — \(nearest.date.formatted(date: .omitted, time: .shortened)) (\(urgency))"
        )

    }

    // MARK: - Language safety
    //
    // The on-device Foundation Model runs language identification on the
    // whole prompt and throws "Unsupported language id detected" when
    // non-English content dominates. User data (holiday calendars,
    // localized place names, Indonesian reminder titles, and older records
    // synced before locale fixes) can carry that content into the prompt.
    //
    // Rather than chase every source, we filter here — the single chokepoint
    // where all context is assembled — dropping any line confidently
    // detected as a non-English language. This is resilient to stale data
    // already in the store, so no reinstall is needed.

    private let recognizer = NLLanguageRecognizer()

    /// Keeps only lines that are English or too short/ambiguous to classify.
    private func englishOnly(_ lines: [String]) -> [String] {
        lines.filter { isEnglishSafe($0) }
    }

    /// Returns the string if it is safe to feed the model, else nil.
    private func englishOrNil(_ text: String) -> String? {
        isEnglishSafe(text) ? text : nil
    }

    /// True when the dominant language is English, or when the recognizer
    /// can't confidently identify a language (short strings, proper nouns,
    /// dates) — in which case it won't tip the prompt's overall detection.
    private func isEnglishSafe(_ text: String) -> Bool {
        recognizer.reset()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return true
        }
        return language == .english
    }

    // MARK: - Gathering

    private func upcomingEvents(limit: Int = 10) -> [String] {

        let now = Date.now

        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now },
            sortBy: [SortDescriptor(\.startDate)]
        )
        descriptor.fetchLimit = limit

        let events = (try? context.fetch(descriptor)) ?? []

        return englishOnly(events.map {
            "\($0.title) — \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
        })

    }

    private func pendingReminders(limit: Int = 10) -> [String] {

        let descriptor = FetchDescriptor<ReminderItem>()

        let reminders = (try? context.fetch(descriptor)) ?? []

        return englishOnly(reminders
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(limit)
            .map { reminder in

                if let dueDate = reminder.dueDate {
                    return "\(reminder.title) — due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
                }

                return "\(reminder.title) — no due date"

            })

    }

    private func insights() -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let insights = (try? context.fetch(descriptor)) ?? []

        return englishOnly(insights.map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return "[\(insight.category.rawValue)] \(insight.title): \(insight.value) (\(origin))"

        })

    }

    private func recentHistory(limit: Int = 20) -> [String] {

        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let items = (try? context.fetch(descriptor)) ?? []

        return englishOnly(items.map {
            "\($0.timestamp.formatted(date: .abbreviated, time: .shortened)) — \($0.title)"
        })

    }

    private func answeredQuestions(limit: Int = 10) -> [String] {

        var descriptor = FetchDescriptor<QuestionAnswer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let answers = (try? context.fetch(descriptor)) ?? []

        return englishOnly(answers.map {
            "Q: \($0.question) — A: \($0.answer)"
        })

    }

}
