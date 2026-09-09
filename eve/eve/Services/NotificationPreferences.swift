//
//  NotificationPreferences.swift
//  Eve
//
//  The per-category notification switches on NotificationSettingsView are
//  app-level preferences. This is the non-View side that reads them so the
//  assistant can gate what it sends. Mirrors the plain-UserDefaults style
//  PermissionManager already uses for "isAIEnabled" etc.
//

import Foundation

/// The three notification kinds the user can toggle. Raw values map each
/// category to the `@AppStorage` key its switch writes in NotificationSettingsView.
enum NotificationCategory: String, CaseIterable {
    case routine, insight, actionable

    /// What each category means, in the words the model is given.
    ///
    /// One list drives both the AI instructions and `isEnabled(forCategory:)`,
    /// so a prompt can never offer a category the app doesn't recognise —
    /// the same move `LocationIconResolver.catalog` makes for icon names.
    nonisolated var meaning: String {
        switch self {
        case .routine:    "for a scheduled commitment or preparation"
        case .insight:    "when driven by a learned pattern or belief about the user"
        case .actionable: "when asking the user to do a concrete task right now"
        }
    }

    /// Just the names, for a short "one of" list.
    nonisolated static var promptNames: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// The names with their meanings, as the instructions phrase them.
    nonisolated static var promptCatalog: String {
        allCases.map { "'\($0.rawValue)' \($0.meaning)" }.joined(separator: "; ")
    }

    var preferenceKey: String {
        switch self {
        case .routine:    "notif.routineReminders"
        case .insight:    "notif.insightAlerts"
        case .actionable: "notif.actionableNotifications"
        }
    }
}

enum NotificationPreferences {

    /// Register the default-ON values once at launch. Without this, a fresh
    /// install reads `false` for a key the user hasn't flipped yet — even
    /// though the toggle UI shows ON — because `bool(forKey:)` returns false
    /// for absent keys. `register(defaults:)` supplies the fallback without
    /// overwriting any real user choice, and shares UserDefaults.standard
    /// with the `@AppStorage` toggles.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            NotificationCategory.routine.preferenceKey: true,
            NotificationCategory.insight.preferenceKey: true,
            NotificationCategory.actionable.preferenceKey: true,
        ])
    }

    /// Whether the user allows notifications of the model-assigned category.
    /// Unknown/garbled category → fail OPEN (send), so a genuine reminder is
    /// never silently dropped on a misclassification.
    static func isEnabled(forCategory raw: String) -> Bool {
        guard let category = NotificationCategory(rawValue: raw.lowercased()) else {
            return true
        }
        return UserDefaults.standard.bool(forKey: category.preferenceKey)
    }
}
