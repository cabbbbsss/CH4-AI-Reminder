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
            UserEvent.self,
            LearnedRoutine.self,
            QuestionAnswer.self,
            ReminderHistory.self
        ])
    }
}
