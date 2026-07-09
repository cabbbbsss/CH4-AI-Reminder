//
//  LocationReminder.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// One reminder shown under a SavedLocation card.
///
/// Two kinds:
/// - System-managed (isSystemManaged = true): AI-generated from a calendar
///   event matched to this place. `itemKey` is that generated text's own
///   normalized form (prevents re-inserting identical wording elsewhere).
///   These are wiped and regenerated on every refresh.
/// - User-owned (isSystemManaged = false): either typed in directly, or a
///   system item the user edited/moved. These survive refresh untouched.
@Model
final class LocationReminder {

    var id: UUID

    var locationID: UUID

    var text: String

    /// Normalized form of this row's own text, or nil for a freeform
    /// reminder the user typed. Tracks provenance across text edits so
    /// refresh never duplicates text the user already owns.
    var itemKey: String?

    /// The source calendar event's title, or nil for a freeform reminder.
    /// Multiple rows can share the same eventTitle (one event often yields
    /// several prep reminders) — used to move every reminder for an event
    /// together when the user reassigns one of them to a different place.
    var eventTitle: String?

    var isSystemManaged: Bool

    /// User ticked this reminder off. Completed rows stay visible (checked)
    /// for the rest of the day and are suppressed from AI regeneration so a
    /// refresh doesn't resurface something the user already handled today —
    /// see `LocationRoutingManager.seedReminders`. Defaulted so SwiftData
    /// can lightweight-migrate the existing persistent store.
    var isCompleted: Bool = false

    /// When it was ticked off. Used to scope the "don't resurface" rule to
    /// the current calendar day: once this is no longer today, the row
    /// becomes regenerable again.
    var completedAt: Date? = nil

    var createdAt: Date

    init(
        locationID: UUID,
        text: String,
        itemKey: String? = nil,
        eventTitle: String? = nil,
        isSystemManaged: Bool = false,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now
    ) {

        self.id = UUID()
        self.locationID = locationID
        self.text = text
        self.itemKey = itemKey
        self.eventTitle = eventTitle
        self.isSystemManaged = isSystemManaged
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt

    }

}
