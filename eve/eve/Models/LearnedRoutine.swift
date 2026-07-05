//
//  LearnedRoutine.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData

@Model
final class LearnedRoutine {

    var place: String

    var averageArrivalHour: Int

    var visitCount: Int

    var confidence: Double

    init(
        place: String,
        averageArrivalHour: Int,
        visitCount: Int,
        confidence: Double
    ) {

        self.place = place
        self.averageArrivalHour = averageArrivalHour
        self.visitCount = visitCount
        self.confidence = confidence

    }

}
