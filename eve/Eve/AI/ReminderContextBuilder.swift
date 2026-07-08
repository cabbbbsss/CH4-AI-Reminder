//
//  ReminderContextBuilder.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData
import NaturalLanguage

/// The only component allowed to gather information for the AI.
/// Reads the SwiftData mirror (kept fresh by EventKitSyncManager)
/// plus insights, history and answers, and condenses everything
/// into one ReminderContext.
final class ReminderContextBuilder {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func build(currentPlace: String?) -> ReminderContext {

        ReminderContext(
            currentDate: .now,
            currentPlace: currentPlace.flatMap(englishOrNil),
            upcomingEvents: upcomingEvents(),
            pendingReminders: pendingReminders(),
            insights: insights(),
            recentHistory: recentHistory(),
            answeredQuestions: answeredQuestions()
        )

    }

    // MARK: - Language safety
    //
    // The on-device Foundation Model runs language identification on the
    // whole prompt and throws "Unsupported language id detected" when
    // non-English content dominates. User data (holiday calendars,
    // localized place names, Indonesian reminder titles, and older records
    // synced before locale fixes) can carry that content into the prompt.
    //
    // Rather than chase every source, we filter here — the single chokepoint
    // where all context is assembled — dropping any line confidently
    // detected as a non-English language. This is resilient to stale data
    // already in the store, so no reinstall is needed.

    private let recognizer = NLLanguageRecognizer()

    /// Keeps only lines that are English or too short/ambiguous to classify.
    private func englishOnly(_ lines: [String]) -> [String] {
        lines.filter { isEnglishSafe($0) }
    }

    /// Returns the string if it is safe to feed the model, else nil.
    private func englishOrNil(_ text: String) -> String? {
        isEnglishSafe(text) ? text : nil
    }

    /// True when the dominant language is English, or when the recognizer
    /// can't confidently identify a language (short strings, proper nouns,
    /// dates) — in which case it won't tip the prompt's overall detection.
    private func isEnglishSafe(_ text: String) -> Bool {
        recognizer.reset()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return true
        }
        return language == .english
    }

    // MARK: - Gathering

    private func upcomingEvents(limit: Int = 10) -> [String] {

        let now = Date.now

        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate >= now },
            sortBy: [SortDescriptor(\.startDate)]
        )
        descriptor.fetchLimit = limit

        let events = (try? context.fetch(descriptor)) ?? []

        return englishOnly(events.map {
            "\($0.title) — \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
        })

    }

    private func pendingReminders(limit: Int = 10) -> [String] {

        let descriptor = FetchDescriptor<ReminderItem>()

        let reminders = (try? context.fetch(descriptor)) ?? []

        return englishOnly(reminders
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(limit)
            .map { reminder in

                if let dueDate = reminder.dueDate {
                    return "\(reminder.title) — due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
                }

                return "\(reminder.title) — no due date"

            })

    }

    private func insights() -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let insights = (try? context.fetch(descriptor)) ?? []

        return englishOnly(insights.map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return "[\(insight.category.rawValue)] \(insight.title): \(insight.value) (\(origin))"

        })

    }

    private func recentHistory(limit: Int = 20) -> [String] {

        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let items = (try? context.fetch(descriptor)) ?? []

        return englishOnly(items.map {
            "\($0.timestamp.formatted(date: .abbreviated, time: .shortened)) — \($0.title)"
        })

    }

    private func answeredQuestions(limit: Int = 10) -> [String] {

        var descriptor = FetchDescriptor<QuestionAnswer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let answers = (try? context.fetch(descriptor)) ?? []

        return englishOnly(answers.map {
            "Q: \($0.question) — A: \($0.answer)"
        })

    }

}
