//
//  ReasoningEngine.swift
//  Eve
//

import Foundation

/// Everything Eve asks a language model to do.
///
/// `FoundationModelService` is the only conformer today, and Eve is on the
/// on-device model deliberately — nothing here is a plan to leave it. The
/// seam exists because the *decision* is worth being able to re-take cheaply:
///
/// - iOS 27 introduced a `LanguageModel` protocol, so the same
///   `LanguageModelSession` can be backed by the on-device model, Private
///   Cloud Compute, or a third-party provider. If Eve ever escalates one task
///   to PCC, it should be one conformer swapped behind this protocol, not an
///   edit threaded through every manager.
/// - It makes the AI surface countable. These six methods are the entire
///   contract; anything a caller wants from a model has to appear here first.
///
/// Note what the signatures already avoid: no Foundation Models type crosses
/// this boundary. Callers deal in `String`, `[String]`, `ReminderContext`,
/// `ReminderDecision`, `OnboardingQuestion`, and `ProposedInsight` — all Eve's
/// own. That was true before the protocol existed; this just writes it down.
///
/// Conformers are expected to throw rather than return empty when the model is
/// unavailable, so callers can tell "nothing to say" from "couldn't ask".
protocol ReasoningEngine {

    /// The main cycle: should Eve speak now, and if so, what about?
    func decide(from context: ReminderContext) async throws -> ReminderDecision

    /// 2-4 concrete prep items for one calendar event.
    func suggestPreparation(forPromptText promptText: String) async throws -> [String]

    /// 1-2 reminders for an event tied to a saved place.
    func suggestLocationReminder(forPromptText promptText: String) async throws -> [String]

    /// Picks one SF Symbol for a saved place, or nil if none fits.
    func classifyPlaceIcon(userName: String, mapName: String?, address: String?) async throws -> String?

    /// Personalised yes/no questions for onboarding.
    func generateOnboardingQuestions(from context: ReminderContext) async throws -> [OnboardingQuestion]

    /// Durable beliefs distilled from the user's context and answers.
    func extractInsights(from context: ReminderContext) async throws -> [ProposedInsight]

}
