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
enum NotificationCategory: String {
    case routine, insight, actionable

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
