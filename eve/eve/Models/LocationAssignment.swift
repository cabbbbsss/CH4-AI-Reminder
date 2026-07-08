//
//  LocationAssignment.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// Remembers where a calendar/reminder item (by normalized title) belongs.
/// Prevents re-classifying the same item on every seed/refresh, and makes
/// user corrections permanent — a userConfirmed assignment is fed back to
/// the AI classifier as a few-shot example for similar future items.
@Model
final class LocationAssignment {

    @Attribute(.unique) var itemKey: String

    var locationID: UUID

    var userConfirmed: Bool

    var updatedAt: Date

    init(
        itemKey: String,
        locationID: UUID,
        userConfirmed: Bool = false,
        updatedAt: Date = .now
    ) {

        self.itemKey = itemKey
        self.locationID = locationID
        self.userConfirmed = userConfirmed
        self.updatedAt = updatedAt

    }

}
