//
//  SavedLocation.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// A place the user has saved on the Locations screen — either a seeded
/// default (Home/Office) or one they added themselves. Reminders shown
/// under it (LocationReminder) are AI-routed from real calendar/reminder
/// data plus anything the user adds manually.
@Model
final class SavedLocation {

    var id: UUID

    var name: String

    var address: String?

    var iconName: String

    var isDefault: Bool

    var sortOrder: Int

    /// True once LocationRoutingManager has attempted to seed reminders
    /// for this location at least once — prevents re-seeding every launch
    /// while still allowing an explicit "refresh" to pick up new items.
    var hasBeenSeeded: Bool

    var createdAt: Date

    init(
        name: String,
        address: String? = nil,
        iconName: String = "mappin.and.ellipse",
        isDefault: Bool = false,
        sortOrder: Int = 0,
        hasBeenSeeded: Bool = false,
        createdAt: Date = .now
    ) {

        self.id = UUID()
        self.name = name
        self.address = address
        self.iconName = iconName
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.hasBeenSeeded = hasBeenSeeded
        self.createdAt = createdAt

    }

}
