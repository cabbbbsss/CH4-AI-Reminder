//
//  HistoryItem.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

enum HistoryItemType: String, Codable, CaseIterable {

    case calendarImported

    case reminderCompleted

    case reminderIgnored

    case reminderSnoozed

    case questionAnswered

    case insightCreated

    case insightUpdated

    case insightEdited

    case locationVisited

}

@Model
final class HistoryItem {

    var timestamp: Date

    var type: HistoryItemType

    var title: String

    var detail: String

    init(
        type: HistoryItemType,
        title: String,
        detail: String = "",
        timestamp: Date = .now
    ) {

        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.detail = detail

    }

}
