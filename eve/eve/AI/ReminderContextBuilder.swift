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

    /// Max characters of an event's notes included in the wide `ReminderContext`.
    /// Notes are the largest attacker-reachable span, and the prompt shares a
    /// 4096-token window (TN3193), so the excerpt is capped rather than sent whole.
    /// Lower this first if busy days push the context over budget.
    private static let eventNotesExcerptLimit = 200

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func build(currentPlace: String?) -> ReminderContext {

        ReminderContext(
            currentDate: .now,
            currentPlace: currentPlace.flatMap(englishOrNil).map { UntrustedText.delimit($0) },
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

    /// One event's prep prompt, plus the vocabulary of everything that went
    /// into it.
    ///
    /// `groundingTerms` exists so the *output* can be checked against the
    /// same material the model was given — see `OutputGrounding`. Rendering
    /// the prompt loses that: by the time it's one string, there's no way to
    /// tell an event title from a date separator. So the builder, which is
    /// the only thing that knows what it selected, hands the vocabulary out
    /// alongside the text.
    struct PreparationPrompt {

        let promptText: String

        /// Content words drawn from every line that reached `promptText` —
        /// the event itself, and the reminders and beliefs that survived
        /// filtering. Already lowercased and stopword-stripped.
        let groundingTerms: Set<String>

        /// Content words of the event *title* alone. Lets the gate discard an
        /// item that merely restates the title ("Bring breakfast" for an event
        /// called "Breakfast") — grounded, well formed, and useless.
        let subjectTerms: Set<String>

    }

    /// A deliberately narrow context for one event's prep checklist.
    ///
    /// Unlike `build(currentPlace:)`, this does NOT include the day's full
    /// list of other calendar events, and reminders/insights are filtered
    /// to ones that are relevant to the event — not just handed over
    /// wholesale with an instruction to "only use if related." The model
    /// doesn't reliably self-filter irrelevant items from a list it's
    /// shown (confirmed: it surfaced an unrelated reminder for one event
    /// even after the calendar list alone was removed), so the filtering
    /// has to happen here, before anything reaches the prompt.
    func buildPreparationContext(
        eventTitle: String,
        eventDate: Date,
        eventNotes: String?,
        eventLocation: String?,
        eventAttendees: String? = nil
    ) -> PreparationPrompt? {

        // The event title is the prompt's subject and can't be filtered
        // out. If it's non-English, the on-device model rejects the whole
        // prompt ("Unsupported language id detected"), so skip the call
        // entirely — the caller shows "nothing specific" instead.
        guard isEnglishSafe(eventTitle) else { return nil }

        func section(_ header: String, _ lines: [String]) -> String {
            guard !lines.isEmpty else { return "\(header):\n- none" }
            return "\(header):\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }

        // Title, location, and notes all come from EventKit — an invite the
        // user merely received can carry anything in them, so each is marked
        // untrusted before it reaches the model. Notes are the largest and
        // freest-form of the three and the likeliest injection carrier.
        var eventLine = "\(UntrustedText.delimit(eventTitle)) — \(eventDate.formatted(date: .omitted, time: .shortened))"

        if let eventLocation, let safeLocation = englishOrNil(eventLocation) {
            eventLine += "\nLocation: \(UntrustedText.delimit(safeLocation))"
        }

        if let eventAttendees, let safeAttendees = englishOrNil(eventAttendees) {
            eventLine += "\nGuests: \(UntrustedText.delimit(safeAttendees))"
        }

        if let eventNotes, let safeNotes = englishOrNil(eventNotes) {
            eventLine += "\nEvent notes: \(UntrustedText.delimit(safeNotes))"
        }

        // The content words of the event, which every match is made against.
        let titleKeywords = keywords(from: eventTitle)
        let eventKeywords = keywords(from: "\(eventTitle) \(eventNotes ?? "")")

        var reminders = relevantReminders(to: eventKeywords)
        var beliefs = relevantInsights(to: eventKeywords)

        // Eve's own corpus: what this *kind* of activity usually needs. The
        // user's rows say a gym session is happening; these say it implies
        // gear. Fires only on an explicit trigger word, so an event the corpus
        // doesn't cover — "Sleep" — correctly retrieves nothing.
        var knowledge = KnowledgeStore
            .facts(matching: eventKeywords)
            .map(\.text)

        // Everything above is ranked but not yet bounded. The window is 4096
        // tokens shared with the instructions, the schema and the response
        // (TN3193), so trim to a budget rather than trusting per-section caps
        // to add up to something safe.
        (reminders, beliefs, knowledge) = Self.fitToBudget(
            reminders: reminders,
            beliefs: beliefs,
            knowledge: knowledge
        )

        var promptText = """
        Event: \(eventLine)

        \(section("Reminders that specifically match this event", reminders))

        \(section("Beliefs about the user that specifically match this event", beliefs))
        """

        // Only added when non-empty: an explicit "none" here invites the model
        // to remark on the absence, and the strict prep instructions already
        // treat an empty answer as correct.
        if !knowledge.isEmpty {
            promptText += "\n\n" + section(
                "General knowledge about this kind of activity",
                knowledge
            )
        }

        // Everything the model was actually shown, so the gate can hold its
        // output to it. The event's location counts even though it isn't part
        // of `eventKeywords` — a prep item naming the venue is grounded.
        //
        // Knowledge chunks MUST be included. Leaving them out was the main
        // predicted regression of this change: the model would correctly use a
        // retrieved chunk, and `OutputGrounding` would then drop the item for
        // naming something it couldn't find in the context.
        var groundingTerms = eventKeywords
        groundingTerms.formUnion(keywords(from: eventLocation ?? ""))
        groundingTerms.formUnion(keywords(from: eventAttendees ?? ""))
        for line in reminders + beliefs + knowledge {
            groundingTerms.formUnion(keywords(from: UntrustedText.strip(line)))
        }

        return PreparationPrompt(
            promptText: promptText,
            groundingTerms: groundingTerms,
            subjectTerms: titleKeywords
        )

    }

    // MARK: - Token budget

    /// Characters per token, for estimating prompt size without an API call.
    ///
    /// Apple gives 3–4 characters per token for Latin scripts (TN3193); 3.5 is
    /// the midpoint. iOS 26.4 added `tokenCount(for:)` for an exact answer, but
    /// Eve deploys to 26.2, so an estimate is what's available. Erring low is
    /// deliberate — over-estimating tokens trims context that would have fit,
    /// which is cheaper than `exceededContextWindowSize`.
    private static let charactersPerToken = 3.5

    /// Tokens allowed for retrieved context in a prep prompt.
    ///
    /// Roughly a quarter of the 4096 window, leaving the rest for the
    /// instructions, the event itself, `EventPreparation`'s schema, and the
    /// response.
    private static let retrievalTokenBudget = 900

    /// Trims the three retrieved sections to fit `retrievalTokenBudget`,
    /// interleaved by priority rather than section.
    ///
    /// Order matters: the user's own reminders and beliefs outrank Eve's
    /// general knowledge, so a crowded event keeps the personal rows and drops
    /// the generic ones. Taking whole sections in turn would instead let a long
    /// reminder list starve the knowledge entirely, or vice versa.
    private static func fitToBudget(
        reminders: [String],
        beliefs: [String],
        knowledge: [String]
    ) -> (reminders: [String], beliefs: [String], knowledge: [String]) {

        var budget = Int(Double(retrievalTokenBudget) * charactersPerToken)

        func take(_ lines: [String]) -> [String] {
            var kept: [String] = []
            for line in lines {
                let cost = line.count + 3   // "- " and the newline
                guard cost <= budget else { break }
                budget -= cost
                kept.append(line)
            }
            return kept
        }

        let keptReminders = take(reminders)
        let keptBeliefs = take(beliefs)
        let keptKnowledge = take(knowledge)

        return (keptReminders, keptBeliefs, keptKnowledge)

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

    // MARK: - Relevance
    //
    // Prevents unrelated reminders/insights from ever reaching the prompt
    // for a given event, rather than trusting the model to ignore them.
    //
    // Matching is hybrid: exact token overlap first, then sentence embeddings
    // for the pairs that share no word at all. The token filter alone was too
    // narrow — an event "Standup" and a reminder "bring laptop" have nothing
    // in common lexically, so the reminder never reached the prompt and the
    // model invented prep items in the gap it left.

    /// Tokenising lives in `OutputGrounding` so retrieval and the output gate
    /// share one definition of a content word — they compare terms with each
    /// other, and two lists that drifted apart would surface as the gate
    /// dropping output that was properly grounded.
    private func keywords(from text: String) -> Set<String> {
        OutputGrounding.contentTerms(of: text)
    }

    /// How strongly `text` relates to the subject, or nil for no relation.
    ///
    /// Shared content words only. More shared words ranks higher, so the
    /// caller's `prefix` keeps the best rows.
    ///
    /// This briefly had a sentence-embedding fallback for pairs sharing no
    /// word. It was removed after measurement: on one- and two-word event
    /// titles — which is what calendars contain — neither `NLEmbedding` nor a
    /// mean-pooled `NLContextualEmbedding` separated related from unrelated
    /// text, and the resulting false matches put a meeting belief into a Sleep
    /// event's prompt. See `KnowledgeStore` for the numbers. Lexical matching
    /// misses real synonyms, but it never invents a match, and a miss shows up
    /// as a quiet Eve rather than a confidently wrong one.
    private func relevance(
        of text: String,
        to subjectKeywords: Set<String>
    ) -> Double? {

        guard !subjectKeywords.isEmpty else { return nil }

        let shared = keywords(from: text).intersection(subjectKeywords)

        return shared.isEmpty ? nil : Double(shared.count)

    }

    private func sharesKeyword(_ text: String, with eventKeywords: Set<String>) -> Bool {
        guard !eventKeywords.isEmpty else { return false }
        return !keywords(from: text).isDisjoint(with: eventKeywords)
    }

    private func relevantReminders(
        to eventKeywords: Set<String>,
        limit: Int = 10
    ) -> [String] {

        let allReminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        let scored: [(reminder: ReminderItem, score: Double)] = allReminders.compactMap { reminder in
            let text = [reminder.title, reminder.notes ?? ""].joined(separator: " ")
            guard let score = relevance(of: text, to: eventKeywords) else {
                return nil
            }
            return (reminder, score)
        }

        // Relevance first, then soonest-due as the tie-break — which is the
        // whole of the old ordering, now applied within a rank instead of
        // across an unranked filter result.
        let sorted = scored.sorted { first, second in
            if first.score != second.score { return first.score > second.score }
            return (first.reminder.dueDate ?? .distantFuture) < (second.reminder.dueDate ?? .distantFuture)
        }.map(\.reminder)

        return englishOnlyDelimiting(sorted.prefix(limit).map { reminder in
            guard let dueDate = reminder.dueDate else {
                return (lead: "", untrusted: reminder.title, trail: " — no due date")
            }
            return (lead: "",
                    untrusted: reminder.title,
                    trail: " — due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
        })

    }

    /// Beliefs relevant to one event, ranked and capped.
    ///
    /// The cap is a fix, not a nicety: this was the one gatherer in the file
    /// with no limit, so on a well-used install the beliefs alone could push
    /// the prep prompt past the on-device model's ~4k window and get it
    /// silently truncated — the same failure `insights(limit:)` documents.
    private func relevantInsights(
        to eventKeywords: Set<String>,
        limit: Int = 8
    ) -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let allInsights = (try? context.fetch(descriptor)) ?? []

        let scored: [(insight: AIInsight, score: Double)] = allInsights.compactMap { insight in
            let text = "\(insight.title): \(insight.value)"
            guard let score = relevance(of: text, to: eventKeywords) else {
                return nil
            }
            return (insight, score)
        }

        // A belief the user confirmed outranks any scored match — the
        // instructions call those ground truth, so they must never be the
        // rows the cap drops (same rule as `insights(limit:)`).
        let now = Date.now
        let sorted = scored.sorted { first, second in
            if first.insight.isUserEdited != second.insight.isUserEdited {
                return first.insight.isUserEdited
            }
            if first.score != second.score { return first.score > second.score }
            return decayedConfidence(first.insight, now: now) > decayedConfidence(second.insight, now: now)
        }.map(\.insight)

        return englishOnlyDelimiting(sorted.prefix(limit).map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return (lead: "[\(insight.category.rawValue)] ",
                    untrusted: "\(insight.title): \(insight.value)",
                    trail: " (\(origin))")

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

        let trail = " — \(nearest.date.formatted(date: .omitted, time: .shortened)) (\(urgency))"

        guard isEnglishSafe(nearest.title + trail) else { return nil }

        return UntrustedText.delimit(nearest.title) + trail

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

    /// Same filter, but for lines built from a trusted frame around one
    /// untrusted span — the span is wrapped for the model (see `UntrustedText`).
    ///
    /// Language detection deliberately runs on the *undelimited* text: the tags
    /// are Latin script and would otherwise bias the recognizer toward English,
    /// silently letting through content this filter exists to drop.
    private func englishOnlyDelimiting(
        _ parts: [(lead: String, untrusted: String, trail: String)]
    ) -> [String] {
        parts
            .filter { isEnglishSafe($0.lead + $0.untrusted + $0.trail) }
            .map { $0.lead + UntrustedText.delimit($0.untrusted) + $0.trail }
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

        return events.compactMap { event -> String? in

            // The title is the event's subject and gates the whole line: a
            // non-English title makes the on-device model reject the prompt,
            // so drop the event (the same rule the title-only version used).
            guard isEnglishSafe(event.title) else { return nil }

            var line = UntrustedText.delimit(event.title)
                + " — \(event.startDate.formatted(date: .abbreviated, time: .shortened))"

            // Location, guests and notes let Eve learn *why* an event matters,
            // not just that it exists — so reminders can be personalised. Each
            // is attacker-reachable invite text, so it is language-filtered and
            // wrapped as untrusted; notes are excerpted to respect the shared
            // 4096-token window.
            if let location = event.location.flatMap(englishOrNil) {
                line += "\n  Location: \(UntrustedText.delimit(location))"
            }

            if let attendees = event.attendees.flatMap(englishOrNil) {
                line += "\n  Guests: \(UntrustedText.delimit(attendees))"
            }

            if let notes = event.notes.flatMap(englishOrNil), !notes.isEmpty {
                let excerpt = notes.count > Self.eventNotesExcerptLimit
                    ? String(notes.prefix(Self.eventNotesExcerptLimit)) + "…"
                    : notes
                line += "\n  Notes: \(UntrustedText.delimit(excerpt))"
            }

            return line
        }

    }

    private func pendingReminders(limit: Int = 10) -> [String] {

        let descriptor = FetchDescriptor<ReminderItem>()

        let reminders = (try? context.fetch(descriptor)) ?? []

        return englishOnlyDelimiting(reminders
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(limit)
            .map { reminder in

                if let dueDate = reminder.dueDate {
                    return (lead: "",
                            untrusted: reminder.title,
                            trail: " — due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                }

                return (lead: "", untrusted: reminder.title, trail: " — no due date")

            })

    }

    /// Confidence, halved for every 30 days since the insight was last seen.
    /// Keeps a fresh 60% belief ahead of a stale 90% one.
    private func decayedConfidence(_ insight: AIInsight, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(insight.lastUpdated) / 86_400)
        return insight.confidence * pow(0.5, days / 30)
    }

    /// The user's accumulated beliefs, ranked and capped.
    ///
    /// This was previously unbounded while every other gatherer here had a
    /// limit — so on a well-used install the beliefs alone could exceed the
    /// on-device model's 4k-token window and the prompt was silently truncated
    /// mid-context. That presents as Eve "ignoring" something it was told,
    /// which is easy to misread as the model being too small.
    ///
    /// The cap is a floor, not a fix. The real answer is retrieval — letting
    /// the model search this content instead of being handed all of it (see
    /// `SpotlightSearchTool`, iOS 27) — at which point this limit can go.
    private func insights(limit: Int = 12) -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let all = (try? context.fetch(descriptor)) ?? []

        // User-confirmed beliefs outrank everything else: the instructions
        // tell the model they are ground truth it must never contradict, so
        // they must never be the rows that fall off the end.
        let now = Date.now
        let ranked = all.sorted { first, second in
            if first.isUserEdited != second.isUserEdited { return first.isUserEdited }
            return decayedConfidence(first, now: now) > decayedConfidence(second, now: now)
        }

        // The category and origin are Eve's own; the title and value are
        // model-generated, so they carry forward anything a past injection
        // managed to write into the store.
        return englishOnlyDelimiting(ranked.prefix(limit).map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return (lead: "[\(insight.category.rawValue)] ",
                    untrusted: "\(insight.title): \(insight.value)",
                    trail: " (\(origin))")

        })

    }

    private func recentHistory(limit: Int = 20) -> [String] {

        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let items = (try? context.fetch(descriptor)) ?? []

        return englishOnlyDelimiting(items.map {
            (lead: "\($0.timestamp.formatted(date: .abbreviated, time: .shortened)) — ",
             untrusted: $0.title,
             trail: "")
        })

    }

    private func answeredQuestions(limit: Int = 10) -> [String] {

        var descriptor = FetchDescriptor<QuestionAnswer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let answers = (try? context.fetch(descriptor)) ?? []

        // The answer is Eve's own Yes/No; the question text was model-generated.
        return englishOnlyDelimiting(answers.map {
            (lead: "Q: ", untrusted: $0.question, trail: " — A: \($0.answer)")
        })

    }

}
