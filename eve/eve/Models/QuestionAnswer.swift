//
//  QuestionAnswer.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData

@Model
final class QuestionAnswer {

    var question: String

    var answer: String

    var createdAt: Date

    init(
        question: String,
        answer: String,
        createdAt: Date = .now
    ) {

        self.question = question
        self.answer = answer
        self.createdAt = createdAt

    }

}
