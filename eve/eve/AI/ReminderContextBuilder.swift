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
            userName: userName(),
            nextUrgentItem: nextUrgentItem(),
            upcomingEvents: upcomingEvents(),
            pendingReminders: pendingReminders(),
            insights: insights(),
            recentHistory: recentHistory(),
            answeredQuestions: answeredQuestions()
        )

    }

    /// The user's chosen name from their profile, or nil if unset.
    private func userName() -> String? {
        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        let name = profile?.name ?? ""
        return name.isEmpty ? nil : name
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
    /// events, reminders, and beliefs are filtered before anything reaches
    /// the prompt — never handed over wholesale for the model to self-filter.
    ///
    /// Matching has two tiers:
    /// 1. Strong — the place's name/address literally appears in the
    ///    event/reminder's own location text, or shares a keyword with its
    ///    title (expanded with Home/Work synonyms for places recognized as
    ///    such — see `placeKind`).
    /// 2. Weak (Home/Work places only) — no textual overlap, but the event
    ///    falls in a time window typical for that kind of place (evenings/
    ///    weekends for Home, weekday work-hours for Work). Flagged as
    ///    "likely" in the prompt so the model treats it as a softer signal.
    /// Custom places ("Gym", etc.) have no recognized kind, so they stay on
    /// strong matching only — a time heuristic wouldn't generalize to them.
    func buildPlaceContext(placeName: String, address: String? = nil) -> String? {

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

        var placeKeywords = keywords(from: placeName)
        if let address {
            placeKeywords.formUnion(keywords(from: address))
        }

        let kind = placeKind(for: placeName)

        switch kind {
        case .home: placeKeywords.formUnion(Self.homeSynonyms)
        case .work: placeKeywords.formUnion(Self.workSynonyms)
        case .other: break
        }

        let visits = visitCount(for: placeName)

        let visitLine = visits > 0
            ? "Visited \(visits) time\(visits == 1 ? "" : "s")"
            : "Not yet visited"

        return """
        Place: \(placeName)
        \(visitLine)

        \(section("Calendar events at or about this place", placeRelatedEvents(placeName: placeName, address: address, keywords: placeKeywords, kind: kind)))

        \(section("Reminders at or about this place", placeRelatedReminders(placeName: placeName, address: address, keywords: placeKeywords)))

        \(section("Beliefs about the user that specifically match this place", relevantInsights(to: placeKeywords)))
        """

    }

    // MARK: - Forgiving place matching
    //
    // The default places (Home/Office) are named generically, so their
    // name/address almost never appears verbatim in real event text. Rather
    // than requiring an address, places recognized as Home- or Work-like get
    // a broader vocabulary (see the synonym sets below) plus a time-of-day/
    // day-of-week fallback for events with no textual overlap at all.

    private enum PlaceKind {
        case home, work, other
    }

    private static let homeIndicators: Set<String> = [
        "home", "house", "apartment", "flat", "residence", "condo"
    ]

    private static let workIndicators: Set<String> = [
        "office", "work", "workplace", "job", "company", "hq", "headquarters"
    ]

    private static let homeSynonyms: Set<String> = [
        "home", "house", "family", "dinner", "breakfast", "lunch", "cook", "cooking",
        "laundry", "groceries", "grocery", "chores", "clean", "cleaning", "rent",
        "sleep", "relax", "kids", "pet", "dog", "cat", "garden"
    ]

    private static let workSynonyms: Set<String> = [
        "work", "office", "meeting", "meetings", "standup", "sync", "call", "calls",
        "client", "project", "deadline", "presentation", "report", "class", "lecture",
        "campus", "academy", "school", "shift", "interview", "review", "sprint", "demo"
    ]

    private func placeKind(for placeName: String) -> PlaceKind {
        let nameKeywords = keywords(from: placeName)
        if !nameKeywords.isDisjoint(with: Self.homeIndicators) { return .home }
        if !nameKeywords.isDisjoint(with: Self.workIndicators) { return .work }
        return .other
    }

    /// True for evenings, nights, and weekends — when someone is typically
    /// home rather than out.
    private func isLikelyHomeTime(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        let isEveningOrNight = hour >= 19 || hour < 7
        return isWeekend || isEveningOrNight
    }

    /// True for weekday work hours.
    private func isLikelyWorkTime(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekday = (2...6).contains(weekday)
        let isWorkHours = (8..<18).contains(hour)
        return isWeekday && isWorkHours
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

    /// Whether/how strongly one event matches a place. `true` = strong
    /// (textual overlap — the real signal), `false` = weak (time-of-day
    /// fallback only, Home/Work places only), `nil` = no match at all.
    private func matchTier(
        for event: CalendarEvent,
        placeName: String,
        address: String?,
        placeKeywords: Set<String>,
        kind: PlaceKind
    ) -> Bool? {

        var locationMatches = false

        if let location = event.location {
            let matchesName: Bool = location.caseInsensitiveCompare(placeName) == .orderedSame
            let matchesAddress: Bool = address.map { location.caseInsensitiveCompare($0) == .orderedSame } ?? false
            let matchesKeyword: Bool = sharesKeyword(location, with: placeKeywords)
            locationMatches = matchesName || matchesAddress || matchesKeyword
        }

        let titleMatches = sharesKeyword(event.title, with: placeKeywords)

        if locationMatches || titleMatches { return true }

        let timeMatches: Bool
        switch kind {
        case .home: timeMatches = isLikelyHomeTime(event.startDate)
        case .work: timeMatches = isLikelyWorkTime(event.startDate)
        case .other: timeMatches = false
        }

        return timeMatches ? false : nil

    }

    private func placeRelatedEvents(placeName: String, address: String?, keywords placeKeywords: Set<String>, kind: PlaceKind, limit: Int = 10) -> [String] {

        let allEvents = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let now = Date.now

        var strong: [CalendarEvent] = []
        var weak: [CalendarEvent] = []

        for event in allEvents {
            switch matchTier(for: event, placeName: placeName, address: address, placeKeywords: placeKeywords, kind: kind) {
            case true: strong.append(event)
            case false: weak.append(event)
            case nil: continue
            }
        }

        // Prefer events closest to now (most relevant), then fill any
        // remaining slots with the closest weak (time-only) matches.
        func closestFirst(_ events: [CalendarEvent]) -> [CalendarEvent] {
            events.sorted { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }
        }

        let selectedStrong = Array(closestFirst(strong).prefix(limit))
        let remainingSlots = max(0, limit - selectedStrong.count)
        let selectedWeak = Array(closestFirst(weak).prefix(remainingSlots))

        let combined = (selectedStrong.map { ($0, true) } + selectedWeak.map { ($0, false) })
            .sorted { $0.0.startDate < $1.0.startDate }

        let lines: [String] = combined.map { event, isStrong in
            let base = "\(event.title) — \(event.startDate.formatted(date: .abbreviated, time: .shortened))"
            return isStrong ? base : "\(base) (likely — based on usual time at this place, not explicit)"
        }

        return englishOnly(lines)

    }

    /// Assigns each upcoming calendar event to **at most one** saved place —
    /// computed once across all places together, unlike per-place matching,
    /// which let the same event win a strong match at one place (e.g. "Cook"
    /// → Home, via keyword) *and* a weak time-of-day match at another (e.g.
    /// the same event happening at 11am on a weekday → Office, via the work
    /// hours fallback) independently, showing it twice.
    ///
    /// Priority per event: a user-confirmed override (ground truth, see
    /// `LocationRoutingManager.confirmAssignment`) > a strong textual match
    /// at any place > a weak time-of-day match, but only if exactly one
    /// place's window applies. Restricted to what's still **upcoming** (a
    /// past "Cook lunch" doesn't need a reminder anymore) and deduplicated
    /// by title so a daily recurring event only contributes its nearest
    /// occurrence. Feeds the Locations screen's per-event prep-reminder
    /// generation (see `LocationRoutingManager`).
    func matchedEventsByLocation(
        _ locations: [(id: UUID, name: String, address: String?)],
        limit: Int = 6
    ) -> [UUID: [CalendarEvent]] {

        struct LocationContext {
            let id: UUID
            let name: String
            let address: String?
            let keywords: Set<String>
            let kind: PlaceKind
        }

        let locationContexts: [LocationContext] = locations.compactMap { location in
            guard isEnglishSafe(location.name) else { return nil }
            var kws = keywords(from: location.name)
            if let address = location.address {
                kws.formUnion(keywords(from: address))
            }
            let kind = placeKind(for: location.name)
            switch kind {
            case .home: kws.formUnion(Self.homeSynonyms)
            case .work: kws.formUnion(Self.workSynonyms)
            case .other: break
            }
            return LocationContext(id: location.id, name: location.name, address: location.address, keywords: kws, kind: kind)
        }

        let locationIDs = Set(locationContexts.map(\.id))

        let now = Date.now

        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now },
            sortBy: [SortDescriptor(\.startDate)]
        )

        let upcoming = (try? context.fetch(descriptor)) ?? []

        let confirmedAssignments = (try? context.fetch(FetchDescriptor<LocationAssignment>())) ?? []
        var confirmedByKey: [String: UUID] = [:]
        for assignment in confirmedAssignments where assignment.userConfirmed {
            confirmedByKey[assignment.itemKey] = assignment.locationID
        }

        var seenTitles = Set<String>()
        var result: [UUID: [CalendarEvent]] = [:]

        for event in upcoming {

            let key = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seenTitles.contains(key) else { continue }

            if let confirmedID = confirmedByKey[key], locationIDs.contains(confirmedID) {
                seenTitles.insert(key)
                result[confirmedID, default: []].append(event)
                continue
            }

            if let strongMatch = locationContexts.first(where: { lc in
                matchTier(for: event, placeName: lc.name, address: lc.address, placeKeywords: lc.keywords, kind: lc.kind) == true
            }) {
                seenTitles.insert(key)
                result[strongMatch.id, default: []].append(event)
                continue
            }

            let weakMatches = locationContexts.filter { lc in
                matchTier(for: event, placeName: lc.name, address: lc.address, placeKeywords: lc.keywords, kind: lc.kind) == false
            }

            if weakMatches.count == 1, let onlyMatch = weakMatches.first {
                seenTitles.insert(key)
                result[onlyMatch.id, default: []].append(event)
            }

        }

        for (id, events) in result {
            result[id] = Array(events.prefix(limit))
        }

        return result

    }

    private func placeRelatedReminders(placeName: String, address: String?, keywords placeKeywords: Set<String>, limit: Int = 10) -> [String] {

        let allReminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        let matching = allReminders.filter { reminder in
            let locationMatches = reminder.location.map { location in
                location.caseInsensitiveCompare(placeName) == .orderedSame
                    || (address.map { location.caseInsensitiveCompare($0) == .orderedSame } ?? false)
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
