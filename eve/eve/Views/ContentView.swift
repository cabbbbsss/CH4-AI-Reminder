//
//  ContentView.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import SwiftUI

struct ContentView: View {
    
    private let calendarService = CalendarService()
    
    @Environment(\.modelContext)
    private var modelContext
    
    var body: some View {
        VStack {
            Button("Load Calendar") {

                Task {

                    try? await calendarService.requestAccess()

                    let events = calendarService.fetchTodayEvents()

                    print(events)

                }

            }
            
            Button("Save Test Event") {

                let manager = RoutineLearningManager(
                    context: modelContext
                )

                try? manager.saveEvent(
                    type: .locationArrival,
                    value: "Office"
                )

            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
