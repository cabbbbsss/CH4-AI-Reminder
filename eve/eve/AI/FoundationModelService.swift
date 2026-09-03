//
//  FoundationModelService.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import FoundationModels

@Generable
struct ProposedInsight {

    @Guide(description: "One of: \(InsightCategory.promptNames)")
    let category: String

    @Guide(description: "Short internal key for this belief, used only for matching and editing — never displayed as standalone text in the UI. Examples: 'Workplace', 'Meeting Format', 'Morning Exercise'")
    let title: String

    @Guide(description: "A complete, natural-language sentence in second person ('You …') that combines the belief topic and its answer into one self-contained, human-readable statement. This is the ONLY text shown to the user in the insight list, so it must make sense without the title. Keep it concise — aim for under 15 words and never exceed 20. Never output a raw answer like 'Yes', 'No', or a bare noun. Examples: 'You review your notes before every meeting.', 'Your meetings are usually held virtually via Zoom.', 'You often study at a café on weekdays.'")
    let value: String

    @Guide(description: "Confidence between 0.0 and 1.0")
    let confidence: Double

    @Guide(description: "One sentence explaining which observations support this belief")
    let sourceSummary: String

}

@Generable
struct EventPreparation {

    /// Deliberately says nothing about how many items or what qualifies as one.
    ///
    /// Two calls fill this type with different rules — `suggestPreparation`
    /// wants 2-4 strictly traceable items, `suggestLocationReminder` wants 1-2
    /// inferred ones — so any count stated here contradicts one of them. It
    /// also used to carry "never invent generic advice", the phrasing
    /// `preparationInstructions` deliberately dropped because it collides with
    /// the retrieved "General knowledge" section (see the note there). Keeping
    /// it on the schema kept that collision alive on the half of the prompt
    /// the rewrite never touched. Format only, then: the behaviour belongs to
    /// whichever instruction string is driving the call.
    @Guide(description: "The items, most important first. Each under 8 words. An empty list is a valid answer.")
    let items: [String]

}

@Generable
struct PlaceIconSuggestion {

    @Guide(description: "The single best-matching icon name, copied exactly from the allowed list in the instructions")
    let iconName: String

}

@Generable
struct ReminderDecision {

    @Guide(description: "Should a reminder be shown right now?")
    let shouldNotify: Bool

    @Guide(description: "The kind of reminder. One of: \(NotificationCategory.promptNames). Use \(NotificationCategory.promptCatalog).")
    let category: String

    @Guide(description: "Notification title, short and friendly. At most 5 words.")
    let title: String

    @Guide(description: "Notification body: ONE sentence, at most 18 words, specific to the current context. Never two sentences, never a list, never an explanation of why you are saying it. Shown in a small chat bubble and as a system notification, so anything longer is cut off. Example: 'Bring your tumbler — you're heading to your usual lunch spot.'")
    let body: String

}

@Generable
struct OnboardingQuestion {

    @Guide(description: "A short yes/no question whose answer will improve reminders. Either confirms a concrete pattern from the user's data (e.g. 'You usually visit the gym on weekday evenings. Correct?') or asks about an important recurring need (e.g. 'Do you take medication on a regular schedule?').")
    let question: String

}

@Generable
struct OnboardingQuestionSet {

    @Guide(description: "5 to 6 concise yes/no onboarding questions, personalised to the context. Mix confirmations of patterns you can see with questions about important recurring needs such as medication, pets, commute, or exercise.")
    let questions: [OnboardingQuestion]

}

@Generable
struct InsightExtraction {

    @Guide(description: "0 to 6 durable beliefs about the user, each grounded ONLY in the provided context — recurring calendar/reminder patterns and the user's onboarding answers. Empty if the context shows nothing durable.")
    let insights: [ProposedInsight]

}

/// The only gateway to Apple's on-device model.
/// Input: ReminderContext. Output: ReminderDecision. Nothing else.
///
/// Conforms to `ReasoningEngine` so callers depend on the shape of the work
/// rather than on Foundation Models itself — see that protocol for why.
final class FoundationModelService: ReasoningEngine {

    /// Throws unless the on-device model is ready to take a request.
    ///
    /// Every entry point below opens with this. It used to be the same nine
    /// lines copy-pasted at each one, which meant the handling of a newly
    /// added `UnavailableReason` would have to be changed in six places.
    private func requireAvailableModel() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))
        }
    }

    // MARK: - Generation options
    //
    // Every call used to run at the framework default, because none passed
    // `GenerationOptions` at all — so no temperature the team discussed was
    // ever actually in effect. These are the knobs, gathered here rather than
    // written as literals at each call so they can be reviewed and tuned as a
    // set.
    //
    // The split is by what the call is *for*: extracting facts wants low
    // variance, writing something a person reads wants some warmth.

    /// Deterministic. For choosing one value from a fixed set, where the same
    /// input returning the same answer matters more than variety.
    private static let deterministic = GenerationOptions(sampling: .greedy)

    /// Low variance, for output that must stay specific and traceable — the
    /// prep lists and the belief extraction, where a wider spread shows up as
    /// invented detail rather than as variety.
    private static let factual = GenerationOptions(temperature: 0.3)

    /// For prose a person reads, where varied phrasing is the point. Still
    /// well below the framework default: the reminder and the onboarding
    /// questions want a little warmth, not surprise.
    private static let conversational = GenerationOptions(temperature: 0.5)

    enum AIError: LocalizedError {

        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                return "Apple Intelligence model unavailable: \(reason)"
            }
        }

    }

    private let instructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You receive a snapshot of the user's context: calendar, reminders, current place, \
    your own current beliefs (AI Insights), recent activity, and answered questions — \
    and, most importantly, the single most time-urgent upcoming commitment.

    Rules:
    - Your job is to catch small, easily-forgotten things related to the MOST URGENT \
    upcoming commitment — not to summarize the whole day. Think: what would this \
    person realistically forget to bring, prepare, or do beforehand?
    - Base your suggestion on the "Most urgent upcoming commitment" field first. If \
    it's none, only suggest something if your own beliefs (AI Insights) or recent \
    activity clearly point to something concrete and near-term — otherwise stay quiet.
    - Decide whether a reminder is genuinely useful RIGHT NOW. Do not notify for \
    things that are far away in time or already handled. Prefer silence over noise.
    - Phrase reminders in a warm, brief, concrete way — one micro-thing, not a list.
    - Keep the body to ONE sentence, at most 18 words. Do not restate the context \
    back to the user, do not explain your reasoning, and do not justify the \
    suggestion — say the one thing and stop. "You've mentioned wanting to…" and \
    "Since your … is …" are openings that always run too long; start with the \
    thing itself instead.
    - Every reminder must name something that appears in the context above — \
    an event, a reminder, a place, or a belief. If you cannot point to the \
    line it came from, say nothing instead.
    - Beliefs marked "confirmed by the user" are ground truth. Never contradict them.
    - You are writing a reminder, not recording what you have learned. Do not \
    restate a belief back as though it were new.
    - If "User's name" is known (not "unknown"), you MAY occasionally open the \
    reminder by addressing them by that name to feel warm and personal — but \
    only once in a while, never in every message, and never when it feels forced.
    - Classify each reminder with a category — use \(NotificationCategory.promptCatalog).

    \(UntrustedText.instructionRule)
    """

    /// The strict prep path.
    ///
    /// The ban on vagueness is phrased as "every item must name a specific
    /// thing" rather than the older "never invent generic advice." That older
    /// rule collided with the retrieved "General knowledge" section the moment
    /// it was added: a corpus of general statements reads exactly like the
    /// thing being forbidden, so the model's safest move was to ignore the
    /// section entirely and retrieval did nothing. Naming the *specificity* of
    /// the output as the requirement keeps "arrive on time" out while letting
    /// "bring your goggles and towel" in.
    private let preparationInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given ONE upcoming event with its own details, the user's pending \
    reminders and durable beliefs (AI Insights), and — when Eve recognises the kind \
    of activity — a short "General knowledge" list about that kind of activity. You \
    are NOT shown the rest of the day's schedule; reason only about the named event.

    Your only job: list 2-4 short, concrete things this person might forget to \
    bring, prepare, or do before THIS event.

    An item may come from these sources and nothing else:
    1. The event's own title, location, or notes.
    2. A reminder or belief whose subject clearly matches the event.
    3. The "General knowledge" list — but ONLY when the event plainly is that kind \
    of activity. A line about flights is for a flight, not for a meeting that \
    happens to mention an airport.

    Prefer 1 and 2 over 3. What the user wrote about this event beats anything \
    general; use 3 only to supply what they would obviously need but never wrote down.

    STRICT rules:
    - Every item must name a specific thing to bring, prepare, or check. "Bring \
    your goggles and towel" is an item. "Arrive on time", "be prepared", "plan \
    ahead" are not — never write those, whichever source suggested them.
    - Never introduce an object or detail that appears in none of the three sources.
    - Do not repeat a "General knowledge" line as written. Turn it into an \
    instruction to this user about this event.
    - If the event is a routine, prayer time, or generic personal block and nothing \
    given is clearly about it, return an EMPTY list. An empty list is a correct answer.

    \(UntrustedText.instructionRule)
    """

    /// Unlike `preparationInstructions` (strict: every item must trace to
    /// something explicitly given, used for Today's Routine where false
    /// confidence about a random meeting would be embarrassing), this
    /// permits ordinary common-sense inference from the event's own
    /// activity — a "Gym" event implies gym gear, a "Cook" event implies
    /// checking ingredients, even with no note saying so. Used only for
    /// events already matched to a specific saved place (see
    /// `LocationRoutingManager`), where the activity itself is the
    /// intentionally-given signal.
    private let locationEventInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given ONE upcoming calendar event tied to one of the user's \
    saved places, any reminders or beliefs that clearly relate to it, and — \
    when Eve recognises the kind of activity — a short "General knowledge" \
    list about that kind of activity. You are NOT shown the rest of the day's \
    schedule — reason only about the named event.

    Your only job: write 1-2 short, concrete reminders of things this person \
    might forget to bring, prepare, or check before THIS event, based on \
    what kind of activity it clearly is (e.g. a meal, a workout, a meeting, \
    a class).

    Rules:
    - Base each reminder on the event's own title, notes, location, a \
    matching reminder/belief, or the "General knowledge" list. Ordinary \
    common-sense inference from the activity itself is fine and expected — \
    e.g. "Gym" → bring workout gear, "Cook" or "Lunch" → check ingredients \
    are on hand, "Meeting" → bring laptop/notes. This is the point of this task.
    - When the "General knowledge" list covers the activity, prefer it over \
    your own assumptions — it says what this kind of activity actually needs, \
    and guessing past it is how wrong details get introduced.
    - Do not invent specifics that aren't implied by the event's own nature \
    (e.g. don't guess a meeting needs an umbrella just because it might rain).
    - If the event is too vague or generic to say anything concrete and \
    useful (e.g. "Sleep", "Free time"), return an EMPTY list — that's a \
    correct, expected answer. Do not force something just to fill it.
    - Never phrase items as generic advice like "be prepared" or "arrive on \
    time" — every item must be a specific, actionable thing to bring, \
    prepare, or check.

    \(UntrustedText.instructionRule)
    """

    /// Built from `LocationIconResolver.catalog` so the icons offered to the
    /// model are exactly the ones validation will accept.
    private var iconInstructions: String {
        """
        You are Eve, an adaptive reminder assistant running privately on the user's device.

        You will be given ONE place the user just saved: the name they gave it, \
        and optionally the map's own name and address for the pin they confirmed.

        Your only job: pick the ONE icon from the allowed list below that best \
        represents what kind of place this is.

        Allowed icons:
        \(LocationIconResolver.promptCatalog)

        Rules:
        - Answer with exactly one icon name, copied exactly from the list above.
        - Judge only from the given name and address — never invent details.
        - The user's own name for the place is the strongest signal (e.g. a \
        place named "Gym" is a gym even if the address says otherwise).
        - If the kind of place is unclear or not covered, use "\(LocationIconResolver.defaultIcon)".

        \(UntrustedText.instructionRule)
        """
    }

    /// Picks the SF Symbol that best represents one just-saved place, from
    /// the fixed catalog in `LocationIconResolver`. Used only when MapKit's
    /// own point-of-interest category couldn't decide (see the resolver).
    /// Returns nil for output outside the catalog — callers keep whatever
    /// provisional icon they already have.
    func classifyPlaceIcon(userName: String, mapName: String?, address: String?) async throws -> String? {

        try requireAvailableModel()

        // The user typed the name; MapKit supplied the other two. All three
        // are text Eve did not author, so all three are marked as such — the
        // catalog check below already bounds the damage, but this is the one
        // prompt that used to sit outside the rule entirely.
        var prompt = "Name the user gave this place: \(UntrustedText.delimit(userName))"

        if let mapName, !mapName.isEmpty, mapName != userName {
            prompt += "\nThe map's own name for the confirmed pin: \(UntrustedText.delimit(mapName))"
        }

        if let address, !address.isEmpty {
            prompt += "\nAddress of the confirmed pin: \(UntrustedText.delimit(address))"
        }

        let session = LanguageModelSession(instructions: iconInstructions)

        let response = try await session.respond(
            to: prompt,
            generating: PlaceIconSuggestion.self,
            options: Self.deterministic
        )

        let icon = response.content.iconName.trimmingCharacters(in: .whitespacesAndNewlines)

        return LocationIconResolver.allowedSymbols.contains(icon) ? icon : nil

    }

    func decide(from context: ReminderContext) async throws -> ReminderDecision {

        try requireAvailableModel()

        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: context.promptText,
            generating: ReminderDecision.self,
            options: Self.conversational
        )

        return response.content

    }

    /// A short, event-specific checklist of easily-forgotten prep items.
    /// `promptText` must be scoped to just the one event (see
    /// `ReminderContextBuilder.buildPreparationContext`) — passing the full
    /// day's context here caused the model to blend in unrelated events.
    func suggestPreparation(forPromptText promptText: String) async throws -> [String] {

        try requireAvailableModel()

        let session = LanguageModelSession(instructions: preparationInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: EventPreparation.self,
            options: Self.factual
        )

        return response.content.items

    }

    /// A short, activity-based reminder for one calendar event already tied
    /// to a saved place (e.g. "Gym" → "Bring your whey and gloves"). Looser
    /// than `suggestPreparation`: common-sense inference from the event's
    /// own activity is expected, not just explicit context. `promptText`
    /// must be scoped to just the one event (see
    /// `ReminderContextBuilder.buildPreparationContext`).
    func suggestLocationReminder(forPromptText promptText: String) async throws -> [String] {

        try requireAvailableModel()

        let session = LanguageModelSession(instructions: locationEventInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: EventPreparation.self,
            options: Self.factual
        )

        return response.content.items

    }

    private let onboardingInstructions = """
    You are Eve, an adaptive reminder assistant setting up on the user's device.

    From the provided context (calendar, reminders, current place, current \
    beliefs, recent activity), produce a short list of yes/no questions whose \
    answers would MOST improve the reminders you give this user.

    Rules:
    - Every question must be answerable with a simple Yes or No.
    - Prefer confirming concrete patterns you can actually see in the context.
    - Also ask about important recurring needs a reminder app should know: \
    medication schedules, caring for a pet, commuting to work, exercise, \
    recurring appointments.
    - Keep each question to one friendly sentence. Do not repeat questions.
    - Never ask about something already listed under "Questions the user has \
    answered" — those are settled. Ask about what you still don't know.

    \(UntrustedText.instructionRule)
    """

    /// Generates personalised onboarding questions from the prepared context.
    func generateOnboardingQuestions(
        from context: ReminderContext
    ) async throws -> [OnboardingQuestion] {

        try requireAvailableModel()

        let session = LanguageModelSession(instructions: onboardingInstructions)

        let response = try await session.respond(
            to: context.promptText,
            generating: OnboardingQuestionSet.self,
            options: Self.conversational
        )

        return response.content.questions

    }

    private let insightExtractionInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    Your job here is NOT to send a reminder. It is to distil durable, useful \
    BELIEFS about the user from the given context, so future reminders can be \
    personalised. Draw ONLY from:
    - Recurring patterns in the calendar events and pending reminders (e.g. a \
    workplace that appears every weekday, a regular gym slot, a weekly class).
    - The user's onboarding answers, shown as "Q: … — A: Yes/No". These are \
    explicit, high-value evidence.

    Rules:
    - Ground every insight in something explicitly present in the context. Never \
    invent or assume beyond it.
    - Turn a "Yes" answer into a positive belief (e.g. Q "Do you take medication \
    on a schedule?" A "Yes" → "You take medication on a regular schedule."). \
    Skip questions answered "No" unless the "No" itself is clearly informative.
    - Each insight's `value` must be a complete second-person sentence ("You …").
    - A belief must still be true next month. Never write "today", "tonight", \
    "right now", "currently", or "heading to" — those describe a moment, not \
    a person.
    - A belief is a statement, not a suggestion. Never write "should", "might", \
    "make sure", "remember to", "try to", or "consider" — that is advice, and \
    advice is not something you have learned.
    - Pick a fitting category (\(InsightCategory.promptNames)) and an honest \
    confidence. Do not duplicate a belief already listed in the context's insights.
    - NEVER create an insight about missing, unknown, or unspecified information \
    (e.g. do NOT say "You haven't specified your location/name"). Absence of data \
    is not a belief — simply omit it.
    - If nothing durable can be grounded, return an empty list.

    \(UntrustedText.instructionRule)
    """

    /// Extracts durable AI Insights from the prepared context — calendar/reminder
    /// patterns plus the user's onboarding answers. Used during onboarding and
    /// whenever we want to grow beliefs without composing a reminder.
    func extractInsights(
        from context: ReminderContext
    ) async throws -> [ProposedInsight] {

        try requireAvailableModel()

        let session = LanguageModelSession(instructions: insightExtractionInstructions)

        let response = try await session.respond(
            to: context.promptText,
            generating: InsightExtraction.self,
            options: Self.factual
        )

        return response.content.insights

    }

}
