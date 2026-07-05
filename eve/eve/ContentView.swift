//
//  ContentView.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Load Calendar") {

                Task {

                    let service = CalendarService()

                    try? await service.requestAccess()

                    let events = service.fetchTodayEvents()

                    print(events)

                }

            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
