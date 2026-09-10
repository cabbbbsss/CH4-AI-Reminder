//
//  RepeatRule.swift
//  Eve
//

import Foundation

/// How often a reminder comes back.
///
/// Stored on `CalendarReminder` as its raw value. Instances are generated one
/// at a time — completing a repeating reminder creates the next one — rather
/// than expanding a whole series up front, which is what Apple's Reminders
/// does and what keeps the store from filling with rows nobody has reached yet.
enum RepeatRule: String, CaseIterable, Identifiable {
    case never, daily, weekdays, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every Day"
        case .weekdays: return "Every Weekday"
        case .weekly: return "Every Week"
        case .monthly: return "Every Month"
        case .yearly: return "Every Year"
        }
    }

    /// The next occurrence after `date`, or nil when the rule doesn't repeat.
    func nextDate(after date: Date) -> Date? {

        let calendar = Calendar.current

        switch self {
        case .never:
            return nil

        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)

        case .weekdays:
            // Step forward until we land on Mon–Fri, so a Friday reminder
            // reappears on Monday rather than Saturday.
            var candidate = date
            for _ in 0..<7 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                    return nil
                }
                candidate = next
                let weekday = calendar.component(.weekday, from: candidate)
                if weekday != 1 && weekday != 7 { return candidate }
            }
            return candidate

        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)

        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)

        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

/// How far ahead of its time a reminder should announce itself.
enum EarlyReminder: Int, CaseIterable, Identifiable {
    case none = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case oneDay = 1440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "At time of reminder"
        case .fiveMinutes: return "5 minutes before"
        case .tenMinutes: return "10 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .twoHours: return "2 hours before"
        case .oneDay: return "1 day before"
        }
    }
}
