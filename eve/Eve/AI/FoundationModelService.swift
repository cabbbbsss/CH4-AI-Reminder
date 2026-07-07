//
//  FoundationModelService.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import FoundationModels

@Generable
struct ReminderDecision {
    @Guide(description: "Should a reminder be shown?")
    let shouldNotify: Bool
    
    @Guide(description: "Notification title")
    let title: String
    
    @Guide(description: "Notification body")
    let body: String
    
    @Guide(description: "Optional follow-up question for the user")
    let followUpQuestion: String?

}
