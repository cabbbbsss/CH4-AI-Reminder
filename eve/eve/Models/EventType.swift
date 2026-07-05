//
//  EventType.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation

enum EventType: String, Codable {

    case locationArrival

    case locationDeparture

    case reminderCompleted

    case reminderIgnored

    case reminderSnoozed

    case answeredQuestion

}
