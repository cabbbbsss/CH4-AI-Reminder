//
//  EveApp.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import SwiftUI
import SwiftData

@main
struct EveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            UserProfile.self,
            AIInsight.self,
            HistoryItem.self,
            QuestionAnswer.self,
            CalendarEvent.self,
            ReminderItem.self
        ])
    }
}
