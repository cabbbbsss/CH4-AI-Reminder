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
/// Input: ReminderContext. Output: ReminderDecision (or onboarding questions).
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
    your own current beliefs (AI Insights), recent activity, and answered questions.

    Rules:
    - Decide whether a reminder is genuinely useful RIGHT NOW. Do not notify for \
    things that are far away in time or already handled. Prefer silence over noise.
    - Phrase reminders in a warm, brief, concrete way.
    - Beliefs marked "confirmed by the user" are ground truth. Never propose a \
    change to them.
    - Propose new insights only when the context contains repeated or explicit \
    evidence. Give each a confidence that honestly reflects the evidence.
    - Ask a follow-up question only when a single answer would meaningfully \
    improve your understanding. Otherwise leave it empty.
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
