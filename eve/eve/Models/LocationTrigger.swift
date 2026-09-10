//
//  LocationTrigger.swift
//  Eve
//

import Foundation

/// Which half of a visit a place-based reminder belongs to.
///
/// Shared by `LocationReminder` and by a `CalendarReminder` pinned to a place,
/// so the same two words mean the same thing wherever a reminder is edited.
enum LocationTrigger: String, CaseIterable, Identifiable {
    case arriving, leaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arriving: return "Arriving"
        case .leaving: return "Leaving"
        }
    }

    var symbol: String {
        switch self {
        case .arriving: return "arrow.down.right.circle"
        case .leaving: return "arrow.up.forward.circle"
        }
    }
}
