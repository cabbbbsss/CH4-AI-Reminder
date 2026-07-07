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

}
