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

    func runOnce(currentPlace: String?) async {

        isThinking = true
        errorMessage = nil

        defer { isThinking = false }

        let reminderContext = contextBuilder.build(currentPlace: currentPlace)

        do {

            let decision = try await foundationModel.decide(from: reminderContext)

            lastDecision = decision
            pendingQuestion = decision.followUpQuestion

            try? insightManager.apply(decision.proposedInsights)

            if decision.shouldNotify {

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
    /// Reuses the same context → model → insights pipeline as `runOnce`.
    func generateInitialInsights(currentPlace: String?) async {

        isThinking = true
        errorMessage = nil

        defer { isThinking = false }

        let reminderContext = contextBuilder.build(currentPlace: currentPlace)

        do {

            let decision = try await foundationModel.decide(from: reminderContext)

            lastDecision = decision
            pendingQuestion = decision.followUpQuestion

            try? insightManager.apply(decision.proposedInsights)

        } catch {
            errorMessage = error.localizedDescription
        }

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
