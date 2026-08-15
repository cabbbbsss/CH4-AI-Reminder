//
//  InsightManager.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

/// Owns every mutation of AIInsight rows.
/// Enforces the core rule in code (not just in the AI prompt):
/// a user-edited insight is ground truth and is never overwritten.
final class InsightManager {

    private let context: ModelContext

    private let historyLogger: HistoryLogger

    init(context: ModelContext) {
        self.context = context
        self.historyLogger = HistoryLogger(context: context)
    }

    // MARK: - AI-proposed changes

    /// - Parameter groundingTerms: the vocabulary of the context the model was
    ///   given. Proposals naming nothing from it are discarded before they can
    ///   be stored. This matters more here than anywhere else in the app: a
    ///   belief persists, and `ReminderContextBuilder.insights` feeds it back
    ///   into every later prompt, so one ungrounded insight keeps re-entering
    ///   the context long after the call that invented it. Pass `nil` to skip
    ///   the check.
    func apply(
        _ proposals: [ProposedInsight],
        groundedIn groundingTerms: Set<String>? = nil
    ) throws {

        let existing = try context.fetch(FetchDescriptor<AIInsight>())

        // Shape before grounding, because a grounded non-belief passes the
        // grounding check comfortably: "Make sure your Tennis Location is
        // quiet" contains "tennis" and "location", both of which were in the
        // context. Only the shape rule catches it.
        let wellFormed = proposals.filter { proposal in
            guard let reason = InsightShape.reasonToReject(proposal.value) else { return true }
            #if DEBUG
            print("[Eve/grounding] insight: rejected (\(reason)) — \"\(proposal.value)\"")
            #endif
            return false
        }

        let proposals = wellFormed

        let admitted: [ProposedInsight]

        if let groundingTerms {
            // Judged on the value — the sentence actually shown to the user —
            // rather than the title, which is a short internal key the model
            // is told to keep generic.
            let values = proposals.map(\.value)
            let kept = Set(
                OutputGrounding.filterLogging(
                    values,
                    groundedIn: groundingTerms,
                    label: "insight"
                )
            )
            admitted = proposals.filter { kept.contains($0.value) }
        } else {
            admitted = proposals
        }

        for proposal in admitted {

            let category = InsightCategory(
                rawValue: proposal.category.lowercased()
            ) ?? .behavior

            let confidence = min(max(proposal.confidence, 0), 1)

            if let match = existing.first(where: {
                $0.title.caseInsensitiveCompare(proposal.title) == .orderedSame
            }) {

                // The user's word beats the model's, always.
                guard !match.isUserEdited else { continue }

                // Skip no-op updates so History stays meaningful.
                guard match.value != proposal.value
                        || abs(match.confidence - confidence) > 0.05
                else { continue }

                match.category = category
                match.value = proposal.value
                match.confidence = confidence
                match.sourceSummary = proposal.sourceSummary
                match.lastUpdated = .now

                try historyLogger.log(
                    .insightUpdated,
                    title: "Eve updated: \(match.title)",
                    detail: match.value
                )

            } else {

                let insight = AIInsight(
                    category: category,
                    title: proposal.title,
                    value: proposal.value,
                    confidence: confidence,
                    sourceSummary: proposal.sourceSummary
                )

                context.insert(insight)

                try historyLogger.log(
                    .insightCreated,
                    title: "Eve learned: \(insight.title)",
                    detail: insight.value
                )

            }

        }

        try context.save()

    }

    // MARK: - Cleanup

    /// Deletes stored beliefs that aren't belief-shaped.
    ///
    /// Fixing generation isn't enough on its own: beliefs persist, and
    /// `ReminderContextBuilder.insights` feeds every stored row back into every
    /// later prompt. Rows written before the shape check existed would keep
    /// influencing Eve indefinitely — one install already held four, including
    /// advice recorded at 100% confidence.
    ///
    /// **Never touches a user-confirmed insight.** Those are the user's own
    /// words, they are ground truth everywhere else in this type, and a
    /// heuristic must not be the one exception. A person is allowed to phrase
    /// their own belief however they like.
    ///
    /// A no-op once the store is clean, so it is safe to call on every launch.
    func pruneMalformed() throws {

        let all = try context.fetch(FetchDescriptor<AIInsight>())

        var removed = 0

        for insight in all where !insight.isUserEdited {

            guard let reason = InsightShape.reasonToReject(insight.value) else { continue }

            #if DEBUG
            print("[Eve/grounding] insight: pruned stored (\(reason)) — \"\(insight.value)\"")
            #endif

            context.delete(insight)
            removed += 1

        }

        guard removed > 0 else { return }

        try context.save()

    }

    // MARK: - User changes

    func recordUserEdit(_ insight: AIInsight, newValue: String) throws {

        insight.value = newValue
        insight.confidence = 1.0
        insight.isUserEdited = true
        insight.sourceSummary = "Set by you."
        insight.lastUpdated = .now

        try historyLogger.log(
            .insightEdited,
            title: "You corrected: \(insight.title)",
            detail: newValue
        )

        try context.save()

    }

    func delete(_ insight: AIInsight) throws {

        try historyLogger.log(
            .insightEdited,
            title: "You removed: \(insight.title)",
            detail: insight.value
        )

        context.delete(insight)

        try context.save()

    }

}
