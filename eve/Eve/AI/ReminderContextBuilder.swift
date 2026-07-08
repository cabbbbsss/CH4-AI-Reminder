//
//  ReminderContextBuilder.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

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
            currentPlace: currentPlace,
            upcomingEvents: upcomingEvents(),
            pendingReminders: pendingReminders(),
            insights: insights(),
            recentHistory: recentHistory(),
            answeredQuestions: answeredQuestions()
        )

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

        return events.map {
            "\($0.title) — \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
        }

    }

    private func pendingReminders(limit: Int = 10) -> [String] {

        let descriptor = FetchDescriptor<ReminderItem>()

        let reminders = (try? context.fetch(descriptor)) ?? []

        return reminders
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(limit)
            .map { reminder in

                if let dueDate = reminder.dueDate {
                    return "\(reminder.title) — due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
                }

                return "\(reminder.title) — no due date"

            }

    }

    private func insights() -> [String] {

        let descriptor = FetchDescriptor<AIInsight>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let insights = (try? context.fetch(descriptor)) ?? []

        return insights.map { insight in

            let confidence = Int(insight.confidence * 100)

            let origin = insight.isUserEdited
                ? "confirmed by the user — do not change"
                : "\(confidence)% confidence"

            return "[\(insight.category.rawValue)] \(insight.title): \(insight.value) (\(origin))"

        }

    }

    private func recentHistory(limit: Int = 20) -> [String] {

        var descriptor = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let items = (try? context.fetch(descriptor)) ?? []

        return items.map {
            "\($0.timestamp.formatted(date: .abbreviated, time: .shortened)) — \($0.title)"
        }

    }

    private func answeredQuestions(limit: Int = 10) -> [String] {

        var descriptor = FetchDescriptor<QuestionAnswer>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let answers = (try? context.fetch(descriptor)) ?? []

        return answers.map {
            "Q: \($0.question) — A: \($0.answer)"
        }

    }

}
