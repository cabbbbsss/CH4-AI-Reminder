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

    func apply(_ proposals: [ProposedInsight]) throws {

        let existing = try context.fetch(FetchDescriptor<AIInsight>())

        for proposal in proposals {

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
