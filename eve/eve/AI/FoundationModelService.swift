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

    @Guide(description: "Inference scratchpad to reason about the context before extracting this insight")
    let thoughtProcess: String

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

    @Guide(description: "Inference scratchpad to reason about the event context before extracting items")
    let thoughtProcess: String

    @Guide(description: "2-4 short, concrete things to bring, prepare, or do before this specific event, based on the given context. Each under 8 words. Empty if nothing specific comes to mind — never invent generic advice.")
    let items: [String]

}

@Generable
struct PlaceIconSuggestion {

    @Guide(description: "The single best-matching icon name, copied exactly from the allowed list in the instructions")
    let iconName: String

}

@Generable
struct ReminderDecision {

    @Guide(description: "Inference scratchpad to analyze urgency and context before deciding on a reminder")
    let thoughtProcess: String

    @Guide(description: "Should a reminder be shown right now?")
    let shouldNotify: Bool

    @Guide(description: "The kind of reminder. One of: routine, insight, actionable. Use 'routine' for scheduled commitments and preparation; 'insight' when driven by a learned pattern/belief about the user; 'actionable' when asking the user to do a concrete task now.")
    let category: String

    @Guide(description: "Notification title, short and friendly. At most 5 words.")
    let title: String

    @Guide(description: "Notification body: ONE sentence, at most 18 words, specific to the current context. Never two sentences, never a list, never an explanation of why you are saying it. Shown in a small chat bubble and as a system notification, so anything longer is cut off. Example: 'Bring your tumbler — you're heading to your usual lunch spot.'")
    let body: String

    @Guide(description: "A clarifying question for the user, ONLY if one is genuinely needed")
    let followUpQuestion: String?

}

@Generable
struct OnboardingQuestion {

    @Guide(description: "A short, simple yes/no question. NEVER ask compound questions. NEVER ask for details like 'when', 'what', 'where', or 'how'. E.g. 'Do you take medication on a schedule?'")
    let question: String

    @Guide(description: "One of: routine, health, pet, commute, work, preference")
    let category: String

}

@Generable
struct OnboardingQuestionSet {

    @Guide(description: "Inference scratchpad to analyze user context before formulating questions")
    let thoughtProcess: String

    @Guide(description: "Concise yes/no onboarding questions based ONLY on the provided context. If the user's data lacks clear patterns, return an empty array [] so the app can use its fallback questions.")
    let questions: [OnboardingQuestion]

}

@Generable
struct InsightExtraction {

    @Guide(description: "Inference scratchpad to identify durable beliefs before extracting insights")
    let thoughtProcess: String

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

    /// Low variance, for output that must stay specific and traceable.
    private static let factual = GenerationOptions(temperature: 0.3)

    /// Between the two: inference from the activity is wanted, invention isn't.
    private static let grounded = GenerationOptions(temperature: 0.5)

    /// For prose a person reads, where varied phrasing is the point.
    private static let conversational = GenerationOptions(temperature: 0.7)

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
    Evaluate user context to generate a single, highly urgent reminder.

    - Base suggestions on the "Most urgent upcoming commitment". If none, rely on "AI Insights" or recent activity.
    - NEVER notify for distant or already handled tasks. Prefer silence.
    - NEVER contradict beliefs marked "confirmed by the user".
    - Output ONE concrete micro-action to bring, prepare, or do.
    - Body MUST be exactly ONE sentence, max 18 words.
    - Start immediately with the action. NEVER use "You've mentioned...", "Since...", or explain reasoning.
    - NEVER restate a belief back as though it were new.
    - Ask a follow-up question ONLY to meaningfully improve understanding.
    - Address user by name occasionally, only if known.

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
    Extract 2-4 concrete preparation items for the provided event.

    - Source items ONLY from the event details, matching beliefs/reminders, or "General knowledge" (if applicable).
    - Prefer user-provided event details over "General knowledge".
    - EVERY item MUST name a specific thing to bring, prepare, or check.
    - NEVER write generic advice (e.g., "arrive on time", "be prepared").
    - NEVER introduce objects or details absent from the provided sources.
    - NEVER copy "General knowledge" verbatim; adapt to the specific event.
    - Return EMPTY list if the event is generic (e.g., routine, prayer) and no specific prep is required.

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
    Extract 1-2 concrete reminders for a location-based event.

    - Base reminders on the event details, matching beliefs/reminders, or "General knowledge".
    - Common-sense inference from the activity is required (e.g. "Gym" → bring workout gear).
    - Prioritize "General knowledge" over assumptions if it covers the activity.
    - NEVER invent specifics not directly implied by the event's nature (e.g., umbrella for a meeting).
    - NEVER output generic advice (e.g., "be prepared"). EVERY item MUST be specific and actionable.
    - Return EMPTY list if the event is too vague (e.g., "Sleep", "Free time").

    \(UntrustedText.instructionRule)
    """

    /// Built from `LocationIconResolver.catalog` so the icons offered to the
    private var iconInstructions: String {
        """
        Select ONE icon from the allowed list representing the given place.

        Allowed icons:
        \(LocationIconResolver.promptCatalog)

        - Output EXACTLY ONE icon name from the list.
        - Judge ONLY from the provided name and address. NEVER invent details.
        - The user-provided name is the strongest signal.
        - Default to "\(LocationIconResolver.defaultIcon)" if unclear or unsupported.
        """
    }

    /// Picks the SF Symbol that best represents one just-saved place, from
    /// the fixed catalog in `LocationIconResolver`. Used only when MapKit's
    /// own point-of-interest category couldn't decide (see the resolver).
    /// Returns nil for output outside the catalog — callers keep whatever
    /// provisional icon they already have.
    func classifyPlaceIcon(userName: String, mapName: String?, address: String?) async throws -> String? {

        try requireAvailableModel()

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
            options: Self.grounded
        )

        return response.content.items

    }

    private let onboardingInstructions = """
    Generate yes/no questions to improve reminder personalization from user context.

    - EVERY question MUST be answerable with a simple Yes or No.
    - NEVER ask compound questions (e.g., "Do you exercise, and if so, when?").
    - NEVER ask open-ended questions using "when", "what", "where", or "how".
    - PRIORITIZE questions that confirm concrete patterns visible in the provided calendar and reminders.
    - ONLY ask about generic topics (like medication, pets, commute) IF they are explicitly hinted at in the context.
    - If there is not enough data to form meaningful questions, return an empty list of questions.
    - Limit each question to ONE sentence.
    - NEVER repeat questions.

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
    Extract durable beliefs (AI Insights) about the user from the provided context.

    - Draw ONLY from recurring patterns in calendar/reminders and onboarding answers.
    - NEVER invent or assume beyond explicit context.
    - Convert "Yes" onboarding answers into positive beliefs.
    - Ignore "No" answers unless highly informative.
    - Insight `value` MUST be a complete second-person sentence ("You...").
    - NEVER duplicate beliefs already listed in the context.
    - NEVER create insights about missing or unknown information. Omit them entirely.
    - Return EMPTY list if no durable beliefs can be grounded.

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
