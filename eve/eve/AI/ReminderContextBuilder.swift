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

    /// Max characters of an event's notes included in a prompt.
    /// Notes are the largest attacker-reachable span, and the prompt shares a
    /// 4096-token window (TN3193), so the excerpt is capped rather than sent whole.
    /// Lower this first if busy days push the context over budget.
    private static let eventNotesExcerptLimit = 200

    /// `text` cut to `eventNotesExcerptLimit`, ellipsised when it was cut.
    private static func excerpt(_ text: String) -> String {
        text.count > eventNotesExcerptLimit
            ? String(text.prefix(eventNotesExcerptLimit)) + "…"
            : text
    }

    private let context: ModelContext

    /// Whether per-event retrieval may run — EVE Plus only.
    ///
    /// The *only* entitlement check in the AI layer. It sits here because this
    /// type is already the single component allowed to gather context, so
    /// "what may be retrieved" is the same decision as "what enters the
    /// prompt", and the managers stay free of subscription logic beyond
    /// handing the answer in.
    ///
    /// Defaults to `false` so a caller that forgets it under-serves rather
    /// than gives the paid path away.
    ///
    /// Scoped to `buildPreparationContext`. `build(currentPlace:)` — the wide
    /// context behind `decide`, and so behind every actual reminder — is
    /// untouched, which is what keeps the free tier working rather than
    /// merely not crashing.
    ///
    /// Read at every build, not captured once. A snapshot taken when the
    /// builder was made was wrong in two ways: Home builds its managers at
    /// launch, usually before RevenueCat's first `CustomerInfo` has arrived,
    /// so even a paying user was treated as Free all session; and a purchase
    /// made mid-session never reached the long-lived managers at all.
    private var personalizedRetrieval: Bool { personalizedRetrievalSource() }

    private let personalizedRetrievalSource: () -> Bool

    /// A builder with a fixed answer — for tests and the prompt tester, which
    /// compare the Free and Plus paths side by side.
    convenience init(context: ModelContext, personalizedRetrieval: Bool = false) {
        self.init(context: context, personalizedRetrievalSource: { personalizedRetrieval })
    }

    private init(context: ModelContext, personalizedRetrievalSource: @escaping () -> Bool) {
        self.context = context
        self.personalizedRetrievalSource = personalizedRetrievalSource
    }

    /// A builder that follows the user's EVE Plus entitlement as it changes.
    /// What the app's managers should use.
    static func followingEntitlement(context: ModelContext) -> ReminderContextBuilder {
        ReminderContextBuilder(
            context: context,
            personalizedRetrievalSource: { SubscriptionService.shared.isPro }
        )
    }

    func build(currentPlace: String?) -> ReminderContext {

        // The per-section caps below never added up to anything: ten events
        // carrying notes, twelve beliefs, twenty history rows and an unbounded
        // preference list can exceed the 4096-token window between them,
        // before the instructions and the schema are counted. The prompt is
        // then silently truncated mid-context, which presents as Eve ignoring
        // something it was told — easy to misread as the model being too small.
        // `insights(limit:)` already called its own cap a floor rather than a
        // fix; this is the ceiling those caps sit under.
        //
        // Trimmed here rather than in `promptText` so the context object holds
        // only what the model is shown: `groundingTerms` is derived from these
        // same fields, and terms from a dropped line would let `OutputGrounding`
        // admit output grounded on context that never reached the prompt.
        //
        // Call order is priority order. The schedule and the user's own
        // beliefs lead — the instructions name them as what a reminder is
        // built from — and the history tail goes first, being the section
        // whose rows repeat each other most.
        var budget = Self.characterBudget(forTokens: Self.contextTokenBudget)

        let events = Self.take(upcomingEvents(), within: &budget)
        let beliefs = Self.take(insights(), within: &budget)
        let preferences = Self.take(contextualPreferences(), within: &budget)
        let answers = Self.take(answeredQuestions(), within: &budget)
        let history = Self.take(recentHistory(), within: &budget)

        let context = ReminderContext(
            currentDate: .now,
            currentPlace: currentPlace.flatMap(englishOrNil).map { UntrustedText.delimit($0) },
            userName: userName(),
            nextUrgentItem: nextUrgentItem(),
            meetingLink: nil,
            eventDescription: nil,
            eventLocation: nil,
            guests: nil,
            upcomingEvents: events,
            insights: beliefs,
            recentHistory: history,
            answeredQuestions: answers,
            contextualPreferences: preferences
        )

        // The budget covers the gathered sections; the headers, the scalar
        // lines and `nextUrgentItem` sit outside it. This is the check that
        // they stay small enough for that to be safe — it fails on the
        // rendered prompt, which is the thing that actually has to fit.
        assert(
            context.promptText.count <= Self.characterBudget(forTokens: 3000),
            "wide context prompt exceeded its estimate: \(context.promptText.count) characters"
        )

        return context

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

        /// True when retrieval *ran and found nothing*, leaving `groundingTerms`
        /// as only the event's own words.
        ///
        /// Callers pass an empty set to `OutputGrounding` in that case, because
        /// the gate and lexical retrieval otherwise fail together on the same
        /// event and compound: retrieval misses, so the only evidence left is
        /// the title, so "shares a term with the context" collapses into
        /// "echoes the event title". A "Tennis" event drops "Bring your racket"
        /// and keeps "Pack tennis shoes" — the gate stops catching invention
        /// and starts rewarding restatement.
        ///
        /// False for a free account, which is the distinction the name carries:
        /// retrieval did not miss, it never ran, so the event's own details are
        /// the whole of what the model was given and holding the output to them
        /// is exactly right. Reading this as "no retrieved terms" would have
        /// un-gated every free prompt — the gate must not weaken with the tier.
        ///
        /// Nothing is unguarded either way: the strict instructions still forbid
        /// introducing objects absent from the prompt, and `subjectTerms` still
        /// discards the vacuous items. Widening a trigger in `knowledge.json`
        /// is what moves a subscriber's event back onto the gated path.
        let retrievalMissed: Bool

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
        eventAttendees: String? = nil,
        eventMeetingURL: String? = nil
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

        // A URL isn't prose, so it skips the language filter (it wouldn't trip
        // the model's check anyway), but it's still attacker-reachable — wrap it.
        if let eventMeetingURL, !eventMeetingURL.isEmpty {
            eventLine += "\nMeeting link: \(UntrustedText.delimit(eventMeetingURL))"
        }

        if let eventAttendees, let safeAttendees = englishOrNil(eventAttendees) {
            eventLine += "\nGuests: \(UntrustedText.delimit(safeAttendees))"
        }

        // Excerpted here, before either use below. Cutting the notes only on
        // their way into `eventLine` would leave `eventKeywords` — which is
        // both what retrieval matches on and what `OutputGrounding` holds the
        // output to — built from text the model was never shown, so a prep
        // item naming something from the cut tail would be admitted as
        // grounded. Same reason the language filter has to apply to both:
        // notes dropped as non-English were still reaching the keywords.
        let notes = eventNotes.flatMap(englishOrNil).map(Self.excerpt)

        if let notes {
            eventLine += "\nEvent notes: \(UntrustedText.delimit(notes))"
        }

        // The content words of the event, which every match is made against.
        let titleKeywords = keywords(from: eventTitle)
        let eventKeywords = keywords(from: "\(eventTitle) \(notes ?? "")")

        // The retrieval half of the prompt, and the whole of what EVE Plus
        // buys here: the user's own beliefs matched to *this* event, and Eve's
        // corpus of what the activity implies. Everything else in this prompt
        // — the event, its notes, location, guests, link — is the free tier's
        // and is assembled identically below.
        var beliefs = personalizedRetrieval ? relevantInsights(to: eventKeywords) : []

        // Eve's own corpus: what this *kind* of activity usually needs. The
        // user's rows say a gym session is happening; these say it implies
        // gear. Fires only on an explicit trigger word, so an event the corpus
        // doesn't cover — "Sleep" — correctly retrieves nothing.
        // Answers the user gave to EVE's own questions. First in the budget
        // below: they are the only source here the user stated outright.
        var confirmed = personalizedRetrieval
            ? confirmedPreferences(to: eventKeywords)
            : []

        // What this person has actually done before events like this. Gated by
        // the same flag as the other two, so the AI layer still has exactly one
        // entitlement check.
        var habits = personalizedRetrieval
            ? completedHabits(to: eventKeywords, before: eventDate)
            : []

        var knowledge = personalizedRetrieval
            ? KnowledgeStore.facts(matching: eventKeywords).map(\.text)
            : []

        // Everything above is ranked but not yet bounded. The window is 4096
        // tokens shared with the instructions, the schema and the response
        // (TN3193), so trim to a budget rather than trusting per-section caps
        // to add up to something safe.
        // Habits sit between the two on purpose: a belief the user confirmed
        // outranks anything inferred, but evidence of what *this* person did
        // outranks a generic statement about the activity.
        var budget = Self.characterBudget(forTokens: Self.retrievalTokenBudget)
        confirmed = Self.take(confirmed, within: &budget)
        beliefs = Self.take(beliefs, within: &budget)
        habits = Self.take(habits, within: &budget)
        knowledge = Self.take(knowledge, within: &budget)

        var promptText = """
        Event: \(eventLine)

        \(section("Beliefs about the user that specifically match this event", beliefs))
        """

        if !confirmed.isEmpty {
            promptText += "\n\n" + section(
                "Items this person confirmed they want for this kind of event",
                confirmed
            )
        }

        // Same rule as the knowledge section below: omitted entirely when
        // empty, never rendered as "none", so an absence of evidence cannot be
        // read as a fact about the user.
        if !habits.isEmpty {
            promptText += "\n\n" + section(
                "What this person has actually done before events like this",
                habits
            )
        }

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
        // Grounds a prep item that names the provider ("Zoom", "Teams") — the
        // host survives keyword extraction from the URL.
        groundingTerms.formUnion(keywords(from: eventMeetingURL ?? ""))
        for line in confirmed + beliefs + habits + knowledge {
            groundingTerms.formUnion(keywords(from: UntrustedText.strip(line)))
        }

        return PreparationPrompt(
            promptText: promptText,
            groundingTerms: groundingTerms,
            subjectTerms: titleKeywords,
            retrievalMissed: personalizedRetrieval
                && confirmed.isEmpty && beliefs.isEmpty && habits.isEmpty && knowledge.isEmpty
        )

    }

    // MARK: - Self-check
    //
    // No test target, and the tier split has two ways to go quietly wrong: the
    // paid path silently retrieving nothing, or the free path silently losing
    // its grounding gate. Both are checked at launch in debug builds against a
    // throwaway in-memory store.

    #if DEBUG
    @MainActor
    static func selfCheck() {

        guard let container = try? ModelContainer(
            for: AIInsight.self, CalendarReminder.self, ContextualPreference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            assertionFailure("context builder self-check could not open an in-memory store")
            return
        }

        let date = Date.now.addingTimeInterval(3600)

        func prompt(pro: Bool, title: String) -> PreparationPrompt? {
            ReminderContextBuilder(
                context: ModelContext(container),
                personalizedRetrieval: pro
            )
            .buildPreparationContext(eventTitle: title, eventDate: date, eventNotes: nil, eventLocation: nil)
        }

        // EVE Plus: the corpus covers "Gym", so retrieval reaches the prompt.
        let plus = prompt(pro: true, title: "Gym")
        assert(
            plus?.promptText.contains("General knowledge") == true,
            "EVE Plus prep prompt lost its retrieved knowledge"
        )
        assert(plus?.retrievalMissed == false, "retrieval hit but was reported as a miss")

        // Free: same event, same everything else, no retrieved sections.
        let free = prompt(pro: false, title: "Gym")
        assert(
            free?.promptText.contains("General knowledge") == false,
            "free prep prompt received retrieved knowledge"
        )
        assert(
            free?.promptText.contains("Gym") == true,
            "free prep prompt lost the event itself, not just the retrieval"
        )

        // ...and the free prompt stays gated. `retrievalMissed` must stay false
        // when retrieval never ran, or every free item skips the disjointness
        // test in `OutputGrounding`.
        assert(free?.retrievalMissed == false, "free path would bypass the grounding gate")

        // A subscriber on an event the corpus says nothing about is the one
        // case that *does* bypass it — see `PreparationPrompt.retrievalMissed`.
        assert(
            prompt(pro: true, title: "Tennis")?.retrievalMissed == true,
            "an unmatched event should report a retrieval miss"
        )

        // MARK: Wide prompt — absent event detail is omitted, not asserted.

        func wide(link: String?, place: String?, desc: String?, guests: [String]?) -> String {
            ReminderContext(
                currentDate: date, currentPlace: nil, userName: nil, nextUrgentItem: nil,
                meetingLink: link, eventDescription: desc, eventLocation: place, guests: guests,
                upcomingEvents: [], insights: [], recentHistory: [],
                answeredQuestions: [], contextualPreferences: []
            ).promptText
        }

        // Production shape: `build(currentPlace:)` passes all four as nil.
        let bare = wide(link: nil, place: nil, desc: nil, guests: nil)
        for absent in ["Meeting link", "Event location", "Event description", "Guests"] {
            assert(!bare.contains(absent), "wide prompt still renders an empty \(absent) line")
        }

        // PromptTester's scenarios do supply them, and must still render.
        let full = wide(link: "https://zoom.us/j/1", place: "Room A", desc: "Quarterly review", guests: ["Sarah"])
        for present in ["Meeting link: https://zoom.us/j/1", "Event location: Room A",
                        "Event description: Quarterly review", "Sarah"] {
            assert(full.contains(present), "wide prompt dropped a populated value: \(present)")
        }

        // MARK: Confirmed answers — the last step of the learning loop.
        //
        // The loop is only real if a stored answer reaches a *later* prompt.
        // These assert that it does, that it does so only for the event it was
        // about, and that a free account never sees it.

        let answerStore = ModelContext(container)
        answerStore.insert(
            ContextualPreference(
                eventType: "Gym",
                items: ["gloves", "whey"],
                confidence: 1.0,
                isUserConfirmed: true
            )
        )
        // Answered, but the user said no — nothing to carry forward.
        answerStore.insert(
            ContextualPreference(
                eventType: "Dentist",
                items: [],
                confidence: 0,
                isUserConfirmed: true
            )
        )

        func answerPrompt(pro: Bool, title: String) -> String {
            ReminderContextBuilder(context: answerStore, personalizedRetrieval: pro)
                .buildPreparationContext(
                    eventTitle: title, eventDate: date, eventNotes: nil, eventLocation: nil
                )?.promptText ?? ""
        }

        assert(
            answerPrompt(pro: true, title: "Gym").contains("gloves"),
            "a confirmed answer never reached a later prep prompt"
        )
        assert(
            !answerPrompt(pro: false, title: "Gym").contains("gloves"),
            "confirmed-answer context leaked to a free account"
        )
        assert(
            !answerPrompt(pro: true, title: "Piano Practice").contains("gloves"),
            "a confirmed answer reached an unrelated event"
        )

        // Customize: ContextualCustomizeView overwrites the row's items in
        // place, so what the user edited — not what the model deduced — is
        // what a later prompt sees.
        let customized = (try? answerStore.fetch(FetchDescriptor<ContextualPreference>()))?
            .first { $0.eventType == "Gym" }
        customized?.items = ["chalk"]
        let afterEdit = answerPrompt(pro: true, title: "Gym")
        assert(afterEdit.contains("chalk"), "a customized answer did not reach a later prompt")
        assert(!afterEdit.contains("gloves"), "the replaced answer was still being retrieved")
        assert(
            !answerPrompt(pro: true, title: "Dentist")
                .contains("confirmed they want for this kind of event"),
            "an empty confirmed answer was rendered as a section"
        )

        // MARK: Habit retrieval — the five cases, in one seeded store.

        let habitStore = ModelContext(container)

        func completed(_ text: String, event: String, daysAgo: Int, occurrence: String) {
            let row = CalendarReminder(
                occurrenceID: occurrence,
                eventTitle: event,
                eventDate: date.addingTimeInterval(-Double(daysAgo) * 86_400),
                text: text
            )
            row.isCompleted = true
            habitStore.insert(row)
        }

        // A pattern: same habit, two earlier occurrences of the same event.
        completed("Print the quarterly deck", event: "Board Meeting", daysAgo: 7, occurrence: "b1")
        completed("Print the quarterly deck", event: "Board Meeting", daysAgo: 14, occurrence: "b2")
        // Irrelevant to a board meeting, and repeated, so only relevance can exclude it.
        completed("Bring the insurance card", event: "Dental Checkup", daysAgo: 3, occurrence: "d1")
        completed("Bring the insurance card", event: "Dental Checkup", daysAgo: 9, occurrence: "d2")
        // Relevant but done once — an incident, not a habit.
        completed("Book the corner room", event: "Board Meeting", daysAgo: 21, occurrence: "b3")

        func habitPrompt(pro: Bool, title: String) -> String {
            ReminderContextBuilder(context: habitStore, personalizedRetrieval: pro)
                .buildPreparationContext(
                    eventTitle: title, eventDate: date, eventNotes: nil, eventLocation: nil
                )?.promptText ?? ""
        }

        let plusBoard = habitPrompt(pro: true, title: "Board Meeting")

        // 1. Free, with the same history present, gets none of it.
        assert(
            !habitPrompt(pro: false, title: "Board Meeting").contains("quarterly deck"),
            "history personalization leaked to a free account"
        )

        // 2. Plus gets the repeated, relevant habit.
        assert(plusBoard.contains("quarterly deck"), "a repeated relevant habit was not retrieved")

        // 3. ...without the repeated but irrelevant one.
        assert(!plusBoard.contains("insurance card"), "an unrelated habit reached the prompt")

        // 4. A single occurrence stays below the threshold.
        assert(!plusBoard.contains("corner room"), "one completion was presented as a habit")

        // 5. No qualifying history means no section at all, not an empty one.
        assert(
            !habitPrompt(pro: true, title: "Piano Practice")
                .contains("actually done before events like this"),
            "an empty habit section was rendered"
        )

        // The belief half, on the exact pair that used to miss: the event says
        // "Hike", the belief says "hikes". Seeded in its own store so the
        // assertions above stay unaffected.
        let seeded = ModelContext(container)
        seeded.insert(
            AIInsight(
                category: .behavior,
                title: "Belief",
                value: "You often forget your sunglasses on morning hikes.",
                confidence: 0.8,
                sourceSummary: "Self-check"
            )
        )
        let hike = ReminderContextBuilder(context: seeded, personalizedRetrieval: true)
            .buildPreparationContext(
                eventTitle: "Mountain Trail Hike",
                eventDate: date,
                eventNotes: nil,
                eventLocation: nil
            )
        assert(
            hike?.promptText.contains("sunglasses") == true,
            "a belief about hikes no longer reaches a Hike event"
        )

    }
    #endif

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

    /// Tokens allowed for the gathered context in the wide prompt.
    ///
    /// Bigger than `retrievalTokenBudget` because this prompt *is* the
    /// context — there is no one event carrying the subject — but still short
    /// of the window: `decide`'s instructions, `ReminderDecision`'s schema
    /// (its `@Guide` descriptions are prompt text too) and the response need
    /// the rest. The same context also feeds `extractInsights`, whose reply is
    /// the longest of the three, so the headroom is sized for that one.
    ///
    /// Rarely binds on an ordinary account; it exists for the heavy ones.
    private static let contextTokenBudget = 2400

    /// The character allowance for `tokens`, which `take` spends.
    private static func characterBudget(forTokens tokens: Int) -> Int {
        Int(Double(tokens) * charactersPerToken)
    }

    /// Greedily takes lines while they fit, spending `budget` as it goes.
    ///
    /// Callers hold the budget and call this once per section, so the call
    /// order *is* the priority order: a crowded prompt keeps the sections
    /// asked for first and drops the tail of the ones asked for last. Handing
    /// whole sections a fixed share each would instead let one long section
    /// starve another, or leave its allowance unspent while the next is cut.
    ///
    /// Stops at the first line that doesn't fit rather than skipping it and
    /// trying the next: every caller passes lines already ranked best-first,
    /// so what follows an over-long line is worth less than it was.
    private static func take(_ lines: [String], within budget: inout Int) -> [String] {

        var kept: [String] = []

        for line in lines {
            let cost = line.count + 3   // "- " and the newline
            guard cost <= budget else { break }
            budget -= cost
            kept.append(line)
        }

        return kept

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

    private static let homeIndicators: Set<String> = Set([
        "home", "house", "apartment", "flat", "residence", "condo"
    ].map(OutputGrounding.stem))

    private static let workIndicators: Set<String> = Set([
        "office", "work", "workplace", "job", "company", "hq", "headquarters"
    ].map(OutputGrounding.stem))

    private static let homeSynonyms: Set<String> = Set([
        "home", "house", "family", "dinner", "breakfast", "lunch", "cook", "cooking",
        "laundry", "groceries", "grocery", "chores", "clean", "cleaning", "rent",
        "sleep", "relax", "kids", "pet", "dog", "cat", "garden"
    ].map(OutputGrounding.stem))

    private static let workSynonyms: Set<String> = Set([
        "work", "office", "meeting", "meetings", "standup", "sync", "call", "calls",
        "client", "project", "deadline", "presentation", "report", "class", "lecture",
        "campus", "academy", "school", "shift", "interview", "review", "sprint", "demo"
    ].map(OutputGrounding.stem))

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

    /// Items the user explicitly confirmed they want for this kind of event.
    ///
    /// The other end of `LearningScheduler`: it asks "should I remind you to
    /// bring your gloves?", the user taps Yes, and `ContextualPreference` is
    /// marked `isUserConfirmed`. Those answers already reached the wide
    /// context behind `decide`; they did not reach this prompt, which is where
    /// per-event prep actually comes from — so a confirmed answer about Gym
    /// never informed a Gym checklist. This closes that loop.
    ///
    /// Matched on `eventType` rather than handed over wholesale, because this
    /// is a per-event prompt and every other source here is filtered the same
    /// way.
    private func confirmedPreferences(
        to eventKeywords: Set<String>,
        limit: Int = 2
    ) -> [String] {

        let prefs = (try? context.fetch(FetchDescriptor<ContextualPreference>())) ?? []

        let matching = prefs
            .filter { $0.isUserConfirmed && !$0.items.isEmpty }
            .compactMap { pref -> (pref: ContextualPreference, score: Double)? in
                guard let score = relevance(of: pref.eventType, to: eventKeywords) else { return nil }
                return (pref, score)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.pref)

        // The event type came from EventKit and the items were model-generated
        // before the user confirmed them, so a confirmed answer is still not
        // trusted text — an injection the user waved through is still an
        // injection.
        return englishOnlyDelimiting(matching.map {
            (lead: "", untrusted: "\($0.eventType): \($0.items.joined(separator: ", "))", trail: "")
        })

    }

    /// Prep items this person has actually ticked off before events like this
    /// one, kept only where they form a pattern.
    ///
    /// Evidence rather than narration. `HistoryItem` looks like the natural
    /// source and is not: it never recorded reminder interactions at all — the
    /// enum cases for them were removed as never-written — so that store holds
    /// only calendar-sync bookkeeping, GPS fixes, and restatements of insights
    /// and answers this builder already retrieves by other means. A completed
    /// `CalendarReminder` is the one place the app records that the user did
    /// something, and `regenerate` deletes only *uncompleted* system rows, so
    /// they accumulate.
    ///
    /// `occurrencesNeeded` is the whole safeguard: one completed item is an
    /// incident, and presenting it as a habit would invent a person. Only a
    /// thing done before two separate earlier occurrences is offered, and
    /// nothing is offered when nothing qualifies.
    private func completedHabits(
        to eventKeywords: Set<String>,
        before cutoff: Date,
        limit: Int = 2,
        occurrencesNeeded: Int = 2
    ) -> [String] {

        // Strictly earlier events only, so this event's own items can never
        // feed themselves back in as evidence of a habit.
        let descriptor = FetchDescriptor<CalendarReminder>(
            predicate: #Predicate { $0.isCompleted && $0.eventDate < cutoff },
            sortBy: [SortDescriptor(\.eventDate, order: .reverse)]
        )

        let completed = (try? context.fetch(descriptor)) ?? []

        // Grouped by what the item *says*, through the shared tokeniser, so
        // "Bring your laptop charger" and "Bring the laptop charger" are one
        // habit. Keying on the raw string would almost never repeat, and the
        // feature would silently never fire.
        var byHabit: [String: (text: String, occurrences: Set<String>)] = [:]

        for row in completed where sharesKeyword(row.eventTitle, with: eventKeywords) {
            let key = keywords(from: row.text).sorted().joined(separator: " ")
            guard !key.isEmpty else { continue }
            // Rows arrive newest first, so the text kept is the most recent
            // phrasing of the habit.
            byHabit[key, default: (row.text, [])].occurrences.insert(row.occurrenceID)
        }

        let patterns = byHabit.values
            .filter { $0.occurrences.count >= occurrencesNeeded }
            .sorted { $0.occurrences.count > $1.occurrences.count }
            .prefix(limit)

        // The text was model-generated and the event title came from EventKit,
        // so both travel as untrusted, exactly like beliefs do.
        return englishOnlyDelimiting(patterns.map {
            (lead: "", untrusted: $0.text, trail: " (done before \($0.occurrences.count) times)")
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

    /// True if any calendar event is still ahead of us. Used to decide whether
    /// it's even worth asking the model, versus showing a deterministic
    /// "day's clear" state.
    ///
    /// Calendar events only, deliberately. Eve's own `CalendarReminder` rows
    /// are generated *from* those events, so they can't be pending when none
    /// is; and the native Reminders app is a store Eve doesn't read — adding
    /// an EventKit reminders fetch here would mean a second permission prompt
    /// to answer a question the calendar already answers.
    func hasAnyPendingCommitment() -> Bool {

        let now = Date.now

        var eventDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now }
        )
        eventDescriptor.fetchLimit = 1

        let eventCount = (try? context.fetchCount(eventDescriptor)) ?? 0

        return eventCount > 0

    }

    /// Finds the single most time-urgent upcoming calendar event,
    /// escalating the search window hour by hour — next
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

        let upcoming: [(title: String, date: Date)] = events.map { ($0.title, $0.startDate) }

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

    /// Below this, the recognizer's guess is noise and the text is let
    /// through. Measured on real title shapes — the split is not close:
    ///
    ///     Gym                                    sv 0.13
    ///     Breakfast                              en 0.14
    ///     Team standup                           id 0.25
    ///     Tennis                                 fr 0.43
    ///     Sleep                                  en 0.44
    ///     Dentist                                tr 0.46
    ///     Standup                                id 0.47
    ///     Lunch with the team at the office…     en 0.99
    ///     Rapat tim pagi ini di kantor pusat     id 1.00
    ///
    /// Anything in 0.5...0.9 separates them; 0.75 sits in the middle of the
    /// gap. Re-measure before moving it — this is the calibration knob for the
    /// whole filter.
    private static let languageConfidenceFloor = 0.75

    /// True when the dominant language is English, or when the recognizer
    /// can't confidently identify one (short strings, proper nouns, dates) —
    /// in which case it won't tip the prompt's overall detection either.
    ///
    /// The confidence floor is the point: this used to read `dominantLanguage`,
    /// which returns its best guess for *any* input and never nil in practice.
    /// So a one-word title was classified on noise — "Gym" is Swedish, "Tennis"
    /// is French, "Standup" is Indonesian — and `buildPreparationContext`
    /// returned nil for them at its opening guard. One- and two-word titles are
    /// what calendars contain, so the prep path was dead for most events, and
    /// the titles that did survive ("Breakfast", en 0.14) passed on a coin
    /// flip rather than on being English.
    private func isEnglishSafe(_ text: String) -> Bool {
        recognizer.reset()
        recognizer.processString(text)
        guard let guess = recognizer.languageHypotheses(withMaximum: 1).first,
              guess.value >= Self.languageConfidenceFloor
        else {
            return true
        }
        return guess.key == .english
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

            // Location, meeting link, guests and notes let Eve learn *why* an
            // event matters, not just that it exists — so reminders can be
            // personalised. Each is attacker-reachable invite text, so it is
            // language-filtered (except the URL, which isn't prose) and wrapped
            // as untrusted; notes are excerpted to respect the shared
            // 4096-token window.
            if let location = event.location.flatMap(englishOrNil) {
                line += "\n  Location: \(UntrustedText.delimit(location))"
            }

            if let meetingURL = event.meetingURL, !meetingURL.isEmpty {
                line += "\n  Meeting link: \(UntrustedText.delimit(meetingURL))"
            }

            if let attendees = event.attendees.flatMap(englishOrNil) {
                line += "\n  Guests: \(UntrustedText.delimit(attendees))"
            }

            if let notes = event.notes.flatMap(englishOrNil), !notes.isEmpty {
                line += "\n  Notes: \(UntrustedText.delimit(Self.excerpt(notes)))"
            }

            return line
        }

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
    
    private func contextualPreferences() -> [String] {
        let prefs = (try? context.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        return englishOnlyDelimiting(prefs.filter { $0.isUserConfirmed && !$0.items.isEmpty }.map {
            (lead: "", untrusted: "\($0.eventType): \($0.items.joined(separator: ", "))", trail: "")
        })
    }

}
