//
//  AIInsight.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

enum InsightCategory: String, Codable, CaseIterable {

    case routine

    case place

    case preference

    case behavior

}

@Model
final class AIInsight {

    var category: InsightCategory

    var title: String

    var value: String

    /// 0.0 ... 1.0 — how sure the assistant is about this belief.
    var confidence: Double

    var lastUpdated: Date

    /// Why the assistant believes this, in plain language.
    /// Shown to the user so the AI's reasoning is never hidden.
    var sourceSummary: String

    /// True once the user has corrected this insight.
    /// A user-edited insight is the source of truth:
    /// the AI may read it, but must never overwrite it.
    var isUserEdited: Bool

    init(
        category: InsightCategory,
        title: String,
        value: String,
        confidence: Double,
        sourceSummary: String,
        lastUpdated: Date = .now,
        isUserEdited: Bool = false
    ) {

        self.category = category
        self.title = title
        self.value = value
        self.confidence = confidence
        self.sourceSummary = sourceSummary
        self.lastUpdated = lastUpdated
        self.isUserEdited = isUserEdited

    }

}
