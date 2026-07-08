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

    @Guide(description: "Short name of the belief, e.g. 'Workplace' or 'Reminder Timing'")
    let title: String

    @Guide(description: "The believed value, e.g. 'Apple Developer Academy'")
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
struct ReminderDecision {

    @Guide(description: "Should a reminder be shown right now?")
    let shouldNotify: Bool

    @Guide(description: "Notification title, short and friendly")
    let title: String

    @Guide(description: "Notification body, specific to the current context")
    let body: String

    @Guide(description: "A clarifying question for the user, ONLY if one is genuinely needed")
    let followUpQuestion: String?

    @Guide(description: "New or updated beliefs about the user, based on the context")
    let proposedInsights: [ProposedInsight]

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

    private let placeInstructions = """
    You are Eve, an adaptive reminder assistant running privately on the user's device.

    You will be given ONE specific place, how many times the user has visited it, \
    and any calendar events, reminders, or beliefs about the user that are \
    specifically tied to that place. You are NOT shown anything unrelated.

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

}
