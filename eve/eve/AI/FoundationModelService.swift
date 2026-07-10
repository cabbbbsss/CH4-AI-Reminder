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

    @Guide(description: "One of: routine, place, preference, behavior")
    let category: String

    @Guide(description: "Short internal key for this belief, used only for matching and editing — never displayed as standalone text in the UI. Examples: 'Workplace', 'Meeting Format', 'Morning Exercise'")
    let title: String

    @Guide(description: "A complete, natural-language sentence in second person ('You …') that combines the belief topic and its answer into one self-contained, human-readable statement. This is the ONLY text shown to the user in the insight list, so it must make sense without the title. Keep it concise (max ~15 words). Never output a raw answer like 'Yes', 'No', or a bare noun. Examples: 'You review your notes before every meeting.', 'Your meetings are usually held virtually via Zoom.', 'You often study at a café on weekdays.'")
    let value: String

    @Guide(description: "Confidence between 0.0 and 1.0")
    let confidence: Double

    @Guide(description: "One sentence explaining which observations support this belief")
    let sourceSummary: String

}

@Generable
struct EventPreparation {

    @Guide(description: "2-4 short, concrete things to bring, prepare, or do before this specific event, based on the given context. Each under 8 words. Empty if nothing specific comes to mind — never invent generic advice.")
    let items: [String]

}

@Generable
struct PlaceReminders {

    @Guide(description: "2-4 short, concrete things Eve has learned to remind the user about when they're at this specific place, based on the given context. Each under 8 words. Empty if nothing specific comes to mind — never invent generic advice.")
    let items: [String]

}

@Generable
struct LocationAssignmentSuggestion {

    @Guide(description: "The exact item title as given, unmodified")
    let itemTitle: String

    @Guide(description: "The exact location name it belongs to, copied exactly from the given list of places, or 'none' if it doesn't clearly belong to any of them")
    let locationName: String

}

@Generable
struct LocationClassification {

    @Guide(description: "Exactly one assignment per item given, in the same order as given")
    let assignments: [LocationAssignmentSuggestion]

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

    @Guide(description: "The kind of reminder. One of: routine, insight, actionable. Use 'routine' for scheduled commitments and preparation; 'insight' when driven by a learned pattern/belief about the user; 'actionable' when asking the user to do a concrete task now.")
    let category: String

    @Guide(description: "Notification title, short and friendly")
    let title: String

    @Guide(description: "Notification body, specific to the current context")
    let body: String

    @Guide(description: "A clarifying question for the user, ONLY if one is genuinely needed")
    let followUpQuestion: String?

    @Guide(description: "New or updated beliefs about the user, based on the context")
    let proposedInsights: [ProposedInsight]

}

@Generable
struct OnboardingQuestion {

    @Guide(description: "A short yes/no question whose answer will improve reminders. Either confirms a concrete pattern from the user's data (e.g. 'You usually visit the gym on weekday evenings. Correct?') or asks about an important recurring need (e.g. 'Do you take medication on a regular schedule?').")
    let question: String

    @Guide(description: "One of: routine, health, pet, commute, work, preference")
    let category: String

}

@Generable
struct OnboardingQuestionSet {

    @Guide(description: "5 to 6 concise yes/no onboarding questions, personalised to the context. Mix confirmations of patterns you can see with questions about important recurring needs such as medication, pets, commute, or exercise.")
    let questions: [OnboardingQuestion]

}

/// The only gateway to Apple's on-device model.
/// Input: ReminderContext. Output: ReminderDecision. Nothing else.
final class FoundationModelService {

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
    - Beliefs marked "confirmed by the user" are ground truth. Never propose a \
    change to them.
    - Propose new insights only when the context contains repeated or explicit \
    evidence. Give each a confidence that honestly reflects the evidence.
    - Ask a follow-up question only when a single answer would meaningfully \
    improve your understanding. Otherwise leave it empty.
    - Classify each reminder with a category: 'routine' for scheduled \
    commitments and preparation, 'insight' when it's driven by a learned \
    pattern or belief about the user, 'actionable' when you're asking the \
    user to do a concrete task right now.
    """

    private let preparationInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given ONE specific upcoming event with its own details, plus the \
    user's pending reminders and durable beliefs about them (AI Insights). You are \
    NOT shown the rest of the day's schedule — reason only about the named event.

    Your only job: list 2-4 short, concrete things this person might forget to \
    bring, prepare, or do before THIS event specifically.

    STRICT rules:
    - Only use information that is directly about the named event — its own \
    location/notes, or a reminder/belief whose subject clearly matches it (e.g. \
    a reminder literally mentioning the event or its activity).
    - Never invent generic advice like "arrive on time" or "be prepared."
    - If the event is a routine, prayer time, or generic personal block, and \
    nothing given is clearly about it, return an EMPTY list. Do not guess just \
    to fill the list — an empty list is a correct, expected answer.
    - Every item must be traceable to something explicitly stated above. \
    When in doubt, leave it out.
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
    saved places, plus any reminders or beliefs that clearly relate to it. \
    You are NOT shown the rest of the day's schedule — reason only about the \
    named event.

    Your only job: write 1-2 short, concrete reminders of things this person \
    might forget to bring, prepare, or check before THIS event, based on \
    what kind of activity it clearly is (e.g. a meal, a workout, a meeting, \
    a class).

    Rules:
    - Base each reminder on the event's own title, notes, location, or a \
    matching reminder/belief. Ordinary common-sense inference from the \
    activity itself is fine and expected — e.g. "Gym" → bring workout gear, \
    "Cook" or "Lunch" → check ingredients are on hand, "Meeting" → bring \
    laptop/notes. This is the point of this task.
    - Do not invent specifics that aren't implied by the event's own nature \
    (e.g. don't guess a meeting needs an umbrella just because it might rain).
    - If the event is too vague or generic to say anything concrete and \
    useful (e.g. "Sleep", "Free time"), return an EMPTY list — that's a \
    correct, expected answer. Do not force something just to fill it.
    - Never phrase items as generic advice like "be prepared" or "arrive on \
    time" — every item must be a specific, actionable thing to bring, \
    prepare, or check.
    """

    private let placeInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given ONE specific place, how many times the user has visited it, \
    and any calendar events, reminders, or beliefs about the user that are \
    specifically tied to that place. You are NOT shown anything unrelated.

    Some calendar events are marked "(likely — based on usual time at this place, \
    not explicit)" — these weren't confirmed to be at this place, just inferred \
    from when they happen (e.g. an evening event guessed as Home). Treat these as \
    weaker signal: only draw on one if it's still concrete and plausible for this \
    place, and never state or imply it's confirmed to happen here.

    Your only job: list 2-4 short, concrete things Eve has learned to remind the \
    user about when they are at THIS place.

    STRICT rules:
    - Only use information directly given about this place — its events, \
    reminders, or matching beliefs. Never invent generic advice like "have a \
    good time" or "stay safe."
    - If nothing given is clearly actionable for this place, return an EMPTY \
    list. An empty list is a correct, expected answer — do not guess.
    - Every item must be traceable to something explicitly stated above.
    """

    private let classificationInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given a list of the user's saved places (name and optional \
    address), a list of previously confirmed item→place assignments (ground \
    truth, made by the user), and a list of new item titles to classify.

    Your only job: for each new item, decide which saved place it belongs to.

    STRICT rules:
    - Only assign an item to a place if the item's own title clearly \
    indicates that place (mentions its name, or something distinctive from \
    its address), OR the item closely matches the pattern of a previously \
    confirmed assignment.
    - Never guess based on vague association. If unsure, use "none."
    - Previously confirmed assignments are ground truth for similar future \
    items — follow the same pattern the user already established.
    - Return exactly one assignment per item given, in the same order, \
    copying each item's title back exactly as given.
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
        """
    }

    /// Picks the SF Symbol that best represents one just-saved place, from
    /// the fixed catalog in `LocationIconResolver`. Used only when MapKit's
    /// own point-of-interest category couldn't decide (see the resolver).
    /// Returns nil for output outside the catalog — callers keep whatever
    /// provisional icon they already have.
    func classifyPlaceIcon(userName: String, mapName: String?, address: String?) async throws -> String? {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        var prompt = "Name the user gave this place: \"\(userName)\""

        if let mapName, !mapName.isEmpty, mapName != userName {
            prompt += "\nThe map's own name for the confirmed pin: \"\(mapName)\""
        }

        if let address, !address.isEmpty {
            prompt += "\nAddress of the confirmed pin: \(address)"
        }

        let session = LanguageModelSession(instructions: iconInstructions)

        let response = try await session.respond(
            to: prompt,
            generating: PlaceIconSuggestion.self
        )

        let icon = response.content.iconName.trimmingCharacters(in: .whitespacesAndNewlines)

        return LocationIconResolver.allowedSymbols.contains(icon) ? icon : nil

    }

    func decide(from context: ReminderContext) async throws -> ReminderDecision {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: context.promptText,
            generating: ReminderDecision.self
        )

        return response.content

    }

    /// A short, event-specific checklist of easily-forgotten prep items.
    /// `promptText` must be scoped to just the one event (see
    /// `ReminderContextBuilder.buildPreparationContext`) — passing the full
    /// day's context here caused the model to blend in unrelated events.
    func suggestPreparation(forPromptText promptText: String) async throws -> [String] {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: preparationInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: EventPreparation.self
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

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: locationEventInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: EventPreparation.self
        )

        return response.content.items

    }

    /// A short, place-specific "what Eve has learned" checklist.
    /// `promptText` must be scoped to just the one place (see
    /// `ReminderContextBuilder.buildPlaceContext`).
    func suggestReminders(forPromptText promptText: String) async throws -> [String] {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: placeInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: PlaceReminders.self
        )

        return response.content.items

    }

    /// Classifies which saved place each given item title belongs to (or
    /// none). `promptText` must already be scoped/language-filtered — see
    /// `ReminderContextBuilder.buildClassificationContext`.
    func classifyItems(forPromptText promptText: String) async throws -> [LocationAssignmentSuggestion] {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: classificationInstructions)

        let response = try await session.respond(
            to: promptText,
            generating: LocationClassification.self
        )

        return response.content.assignments

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
    """

    /// Generates personalised onboarding questions from the prepared context.
    func generateOnboardingQuestions(
        from context: ReminderContext
    ) async throws -> [OnboardingQuestion] {

        switch SystemLanguageModel.default.availability {

        case .available:
            break

        case .unavailable(let reason):
            throw AIError.unavailable(String(describing: reason))

        }

        let session = LanguageModelSession(instructions: onboardingInstructions)

        let response = try await session.respond(
            to: context.promptText,
            generating: OnboardingQuestionSet.self
        )

        return response.content.questions

    }

}
