//
//  PromptTesterView.swift
//  Eve
//

import SwiftUI

#if DEBUG
struct PromptTesterView: View {
    @StateObject private var tester = PromptTester()
    @State private var selectedScenario: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                if tester.scenarios.isEmpty {
                    Text("Loading Scenarios...")
                        .foregroundColor(.gray)
                } else {
                    Picker("Scenario", selection: $selectedScenario) {
                        ForEach(Array(tester.scenarios.keys.sorted()), id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .onAppear {
                        if selectedScenario.isEmpty, let first = tester.scenarios.keys.sorted().first {
                            selectedScenario = first
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Test Reminder Decision") {
                        Task { await tester.runReminderDecision(scenarioName: selectedScenario) }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Event Prep") {
                        Task { await tester.runEventPreparation(scenarioName: selectedScenario) }
                    }
                    .buttonStyle(.bordered)
                }
                
                HStack(spacing: 12) {
                    Button("Test Insight Extraction") {
                        Task { await tester.runInsightExtraction(scenarioName: selectedScenario) }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Test Onboarding Qs") {
                        Task { await tester.runOnboardingQuestions(scenarioName: selectedScenario) }
                    }
                    .buttonStyle(.bordered)
                }
                
                if tester.isTesting {
                    ProgressView("Generating...")
                        .padding()
                } else if !tester.lastResult.isEmpty {
                    
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // RAG Status
                        HStack {
                            Text("RAG Status:")
                                .font(.headline)
                            if tester.ragUsed {
                                Text("Active (Injected context)")
                                    .foregroundColor(.green)
                                    .bold()
                            } else {
                                Text("Inactive (Base context only)")
                                    .foregroundColor(.orange)
                                    .bold()
                            }
                        }
                        
                        // Prompt Instructions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Prompt & Instructions")
                                .font(.headline)
                            Text(tester.currentInstructions)
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Prompt Text
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Context Provided (Prompt Text)")
                                .font(.headline)
                            Text(tester.currentPromptText)
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Thought Process
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model Thought Process")
                                .font(.headline)
                            Text(tester.currentThoughtProcess)
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Final Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Final Output")
                                .font(.headline)
                            Text(tester.lastResult)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Prompt Tester")
    }
}
#endif
