//
//  AssistantManager.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

/// Orchestrates one full assistant cycle:
/// build ReminderContext → ask the Foundation Model → apply the decision
/// (notification, insight changes, follow-up question).
@Observable
final class AssistantManager {

    private(set) var isThinking = false

    private(set) var lastDecision: ReminderDecision?

    private(set) var pendingQuestion: String?

    private(set) var errorMessage: String?

    private let contextBuilder: ReminderContextBuilder

    private let foundationModel = FoundationModelService()

    private let insightManager: InsightManager

    private let notificationService: NotificationService

    private let historyLogger: HistoryLogger

    private let modelContext: ModelContext

    init(context: ModelContext, notificationService: NotificationService) {
        self.contextBuilder = ReminderContextBuilder(context: context)
        self.insightManager = InsightManager(context: context)
        self.notificationService = notificationService
        self.historyLogger = HistoryLogger(context: context)
        self.modelContext = context
    }

    /// Runs one assistant cycle: build context → ask the model → apply
    /// insights (and optionally schedule a notification).
    ///
    /// - Parameter notify: when false, the decision is still computed and
    ///   insights are applied, but no notification is scheduled. Used during
    ///   onboarding and for the silent suggestion refresh on the Home screen.
    func runOnce(currentPlace: String?, notify: Bool = true) async {

        isThinking = true
        errorMessage = nil
        pendingQuestion = nil

        defer { isThinking = false }

        // Nothing on the calendar and nothing in reminders — there's
        // genuinely nothing to reason about, so skip the model entirely.
        // Faster, always available, and avoids any risk of a model error
        // for a case that has one obvious right answer.
        guard contextBuilder.hasAnyPendingCommitment() else {
            lastDecision = ReminderDecision(
                shouldNotify: false,
                category: "routine",
                title: "All clear",
                body: "Your day's wide open — I'll keep watch and let you know if anything comes up.",
                followUpQuestion: nil,
                proposedInsights: []
            )
            return
        }

        let reminderContext = contextBuilder.build(currentPlace: currentPlace)

        do {

            let decision = try await foundationModel.decide(from: reminderContext)

            lastDecision = decision
            pendingQuestion = decision.followUpQuestion

            try? insightManager.apply(decision.proposedInsights)

            if notify && decision.shouldNotify
                && NotificationPreferences.isEnabled(forCategory: decision.category) {

                try? await notificationService.scheduleReminder(
                    title: decision.title,
                    body: decision.body
                )

            }

        } catch {
            errorMessage = error.localizedDescription
        }

    }

    /// Onboarding pass: learn insights from the freshly-imported context,
    /// WITHOUT sending a notification (the user hasn't finished setup yet).
    func generateInitialInsights(currentPlace: String?) async {
        await runOnce(currentPlace: currentPlace, notify: false)
    }

    /// Distils durable AI Insights from the current context — calendar/reminder
    /// patterns and the user's onboarding answers — and applies them. Unlike
    /// `generateInitialInsights`, this uses the dedicated insight-extraction
    /// prompt (no reminder decision), so it reliably produces beliefs even when
    /// there's no urgent event to react to. Used at the end of onboarding.
    func learnInsights(currentPlace: String?) async {

        isThinking = true
        errorMessage = nil

        defer { isThinking = false }

        let reminderContext = contextBuilder.build(currentPlace: currentPlace)

        do {
            let proposed = try await foundationModel.extractInsights(from: reminderContext)
            try? insightManager.apply(proposed)
        } catch {
            errorMessage = error.localizedDescription
        }

    }

    /// Asks the model for personalised yes/no onboarding questions.
    /// Returns [] on any failure — the caller supplies a fallback set.
    func onboardingQuestions(currentPlace: String?) async -> [OnboardingQuestion] {
        let reminderContext = contextBuilder.build(currentPlace: currentPlace)
        return (try? await foundationModel.generateOnboardingQuestions(
            from: reminderContext
        )) ?? []
    }

    /// A short, event-specific prep checklist for one calendar event —
    /// used by the expandable rows in Today's Routine. Returns an empty
    /// array on failure (unavailable model, language rejection, etc.) so
    /// callers can just show "nothing specific" rather than an error.
    ///
    /// Deliberately scoped to just this one event (not the day's full
    /// context) — see `ReminderContextBuilder.buildPreparationContext`.
    func suggestPreparation(
        forEventTitled title: String,
        at date: Date,
        notes: String?,
        location: String?
    ) async -> [String] {

        guard let promptText = contextBuilder.buildPreparationContext(
            eventTitle: title,
            eventDate: date,
            eventNotes: notes,
            eventLocation: location
        ) else { return [] }

        return (try? await foundationModel.suggestPreparation(forPromptText: promptText)) ?? []

    }

    /// A short, place-specific "what Eve has learned" checklist — used by
    /// the Locations screen. Returns an empty array on failure so callers
    /// can show "nothing learned yet" rather than an error.
    ///
    /// Deliberately scoped to just this one place — see
    /// `ReminderContextBuilder.buildPlaceContext`.
    func suggestReminders(forPlace placeName: String) async -> [String] {

        guard let promptText = contextBuilder.buildPlaceContext(placeName: placeName) else { return [] }

        return (try? await foundationModel.suggestReminders(forPromptText: promptText)) ?? []

    }

    /// Stores the user's answer to Eve's follow-up question.
    /// It becomes context for every future decision.
    func answerPendingQuestion(with answer: String) {

        guard let question = pendingQuestion else { return }

        modelContext.insert(
            QuestionAnswer(question: question, answer: answer)
        )

        try? historyLogger.log(
            .questionAnswered,
            title: question,
            detail: answer
        )

        try? modelContext.save()

        pendingQuestion = nil

    }

}
