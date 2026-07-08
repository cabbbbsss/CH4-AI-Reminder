//
//  LocationReminder.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// One reminder shown under a SavedLocation card. Either routed here by
/// LocationRoutingManager from a real calendar event/reminder title
/// (isAISeeded = true), or typed in directly by the user.
@Model
final class LocationReminder {

    var id: UUID

    var locationID: UUID

    var text: String

    var isAISeeded: Bool

    var createdAt: Date

    init(
        locationID: UUID,
        text: String,
        isAISeeded: Bool = false,
        createdAt: Date = .now
    ) {

        self.id = UUID()
        self.locationID = locationID
        self.text = text
        self.isAISeeded = isAISeeded
        self.createdAt = createdAt

    }

}
