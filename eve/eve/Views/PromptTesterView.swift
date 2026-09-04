//
//  PromptTesterView.swift
//  Eve
//

import SwiftUI

#if DEBUG
struct PromptTesterView: View {
    @StateObject private var tester = PromptTester()
    @State private var selectedScenario = "Busy Executive"
    
    var body: some View {
        Form {
            Section(header: Text("Configuration")) {
                Picker("Scenario", selection: $selectedScenario) {
                    ForEach(Array(tester.scenarios.keys.sorted()), id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
            }
            
            Section(header: Text("Run AI Tasks")) {
                Button("Test Reminder Decision") {
                    Task { await tester.runReminderDecision(scenarioName: selectedScenario) }
                }
                
                Button("Test Event Preparation") {
                    Task { await tester.runEventPreparation(scenarioName: selectedScenario) }
                }
                
                Button("Test Insight Extraction") {
                    Task { await tester.runInsightExtraction(scenarioName: selectedScenario) }
                }
                
                Button("Test Onboarding Questions") {
                    Task { await tester.runOnboardingQuestions(scenarioName: selectedScenario) }
                }
            }
            
            if tester.isTesting {
                HStack {
                    ProgressView()
                    Text("Model is thinking...")
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            } else if !tester.lastResult.isEmpty {
                Section(header: Text("Last Result")) {
                    Text(tester.lastResult)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Check Xcode Console for full logs & Thought Process")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("AI Prompt Tester")
    }
}

#Preview {
    PromptTesterView()
}
#endif
