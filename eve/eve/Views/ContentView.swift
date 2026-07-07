//
//  ContentView.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    var body: some View {
        TabView {

            Tab("Today", systemImage: "sun.max") {
                TodayView()
            }

            Tab("Insights", systemImage: "brain") {
                InsightsView()
            }

            Tab("History", systemImage: "clock") {
                HistoryView()
            }

        }
    }

}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                UserProfile.self,
                AIInsight.self,
                HistoryItem.self,
                QuestionAnswer.self,
                CalendarEvent.self,
                ReminderItem.self
            ],
            inMemory: true
        )
}
