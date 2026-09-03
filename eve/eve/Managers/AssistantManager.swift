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
/// (notification, insight changes).
@Observable
final class AssistantManager {

    private(set) var isThinking = false

    private(set) var lastDecision: ReminderDecision?

    private(set) var errorMessage: String?

    private let contextBuilder: ReminderContextBuilder

    private let foundationModel = FoundationModelService()

    private let insightManager: InsightManager

    private let notificationService: NotificationService

    init(context: ModelContext, notificationService: NotificationService) {
        self.contextBuilder = ReminderContextBuilder(context: context)
        self.insightManager = InsightManager(context: context)
        self.notificationService = notificationService
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
                body: "Your day's wide open — I'll keep watch and let you know if anything comes up."
            )
            return
        }

        let reminderContext = contextBuilder.build(currentPlace: currentPlace)

        do {

            let decision = grounded(
                try await foundationModel.decide(from: reminderContext),
                in: reminderContext
            )

            lastDecision = decision

            if notify && decision.shouldNotify
                && NotificationPreferences.isEnabled(forCategory: decision.category) {

                try? await notificationService.scheduleReminder(
                    title: decision.title,
                    body: decision.body
                )

            }

            // Everything the user is waiting on is done; drop the spinner
            // before the second model call so learning never delays the
            // reminder they tapped for.
            isThinking = false

            // A SEPARATE call, deliberately. These used to come back from
            // `decide` in the same response, and the model — writing a
            // notification at a conversational temperature — filled the belief
            // field with the notification sentence. "Make sure your Tennis
            // Location is comfortable and quiet" was stored as something Eve
            // had learned about the user, at 100% confidence. Extraction has
            // its own strict instructions and a low temperature, and asking
            // for one kind of output at a time is what keeps them apart.
            await applyInsights(from: reminderContext)

        } catch {
            errorMessage = error.localizedDescription
        }

    }

    /// Distils beliefs from an already-built context and stores the ones that
    /// survive validation. Shared by `runOnce` and `learnInsights` so the
    /// context is assembled once per cycle rather than twice.
    private func applyInsights(from context: ReminderContext) async {

        guard let proposed = try? await foundationModel.extractInsights(from: context) else {
            return
        }

        try? insightManager.apply(proposed, groundedIn: context.groundingTerms)

    }

    /// Silences a reminder whose body is about nothing in the context.
    ///
    /// Deliberately the weakest check in the app. A prep item is one of a
    /// list and can be dropped on its own; this is the single thing Eve was
    /// going to say, so a false positive costs a real reminder. It therefore
    /// only fires on the unambiguous case — the body shares *no* content term
    /// at all with the context it was built from, which a reminder genuinely
    /// about the user's next commitment essentially cannot do.
    ///
    /// Rewritten to `shouldNotify: false` rather than discarded: Home already
    /// renders that as "Nothing urgent right now", so the quiet path is one
    /// the UI understands, and no notification is scheduled.
    private func grounded(
        _ decision: ReminderDecision,
        in context: ReminderContext
    ) -> ReminderDecision {

        guard decision.shouldNotify else { return decision }

        let result = OutputGrounding.filter(
            [decision.body],
            groundedIn: context.groundingTerms
        )

        guard result.kept.isEmpty else { return decision }

        #if DEBUG
        print("[Eve/grounding] decision: silenced ungrounded reminder — \"\(decision.body)\"")
        #endif

        return ReminderDecision(
            shouldNotify: false,
            category: decision.category,
            title: decision.title,
            body: decision.body
        )

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

        await applyInsights(from: contextBuilder.build(currentPlace: currentPlace))

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

        guard let prompt = contextBuilder.buildPreparationContext(
            eventTitle: title,
            eventDate: date,
            eventNotes: notes,
            eventLocation: location
        ) else { return [] }

        let items = (try? await foundationModel.suggestPreparation(
            forPromptText: prompt.promptText
        )) ?? []

        // The prep instructions demand every item be traceable to something
        // stated in the prompt; this holds the output to it. An item that
        // fails is dropped, not replaced — the caller already treats an empty
        // list as the correct "nothing specific" answer.
        return OutputGrounding.filterLogging(
            items,
            groundedIn: prompt.groundingTerms,
            notRestating: prompt.subjectTerms,
            label: "prep/\(title)"
        )

    }

}
