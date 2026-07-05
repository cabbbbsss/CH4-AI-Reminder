//
//  UserEvent.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData

@Model
final class UserEvent {

    var timestamp: Date

    var type: EventType

    var value: String

    init(
        timestamp: Date = .now,
        type: EventType,
        value: String
    ) {

        self.timestamp = timestamp
        self.type = type
        self.value = value

    }

}
