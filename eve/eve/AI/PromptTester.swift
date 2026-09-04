//
//  PromptTester.swift
//  Eve
//

import Foundation
import Combine
import SwiftUI
import FoundationModels

#if DEBUG

@MainActor
final class PromptTester: ObservableObject {
    private let modelService = FoundationModelService()
    
    @Published var isTesting = false
    @Published var lastResult: String = ""

    // MARK: - Mock Scenarios
    
    let scenarios: [String: ReminderContext] = [
        "Busy Executive": ReminderContext(
            currentDate: Date(),
            currentPlace: "Office",
            userName: "Alex",
            nextUrgentItem: "Board Meeting at 2:00 PM (Location: Conference Room A)",
            upcomingEvents: [
                "Quarterly Review at 4:00 PM",
                "Flight to Tokyo at 8:00 PM (Terminal 3)"
            ],
            pendingReminders: [
                "Review Q3 financial reports",
                "Approve marketing budget"
            ],
            insights: [
                "You prefer printed notes for board meetings.",
                "You always arrive at the airport 2 hours early."
            ],
            recentHistory: ["Arrived at Office"],
            answeredQuestions: ["Q: Do you commute by train? A: No"]
        ),
        "Student Morning": ReminderContext(
            currentDate: Date(),
            currentPlace: "Dorm",
            userName: "Jamie",
            nextUrgentItem: "Advanced Calculus Exam at 9:00 AM",
            upcomingEvents: [
                "Group Study at Library at 12:00 PM"
            ],
            pendingReminders: [
                "Bring student ID",
                "Return library books"
            ],
            insights: [
                "You study better with noise-canceling headphones."
            ],
            recentHistory: ["Dismissed alarm", "Opened notes app"],
            answeredQuestions: ["Q: Do you take morning classes? A: Yes"]
        ),
        "Weekend Hiker": ReminderContext(
            currentDate: Date(),
            currentPlace: "Home",
            userName: "Sam",
            nextUrgentItem: "Mountaineering Trip at 6:00 AM",
            upcomingEvents: [],
            pendingReminders: [
                "Pack trail mix",
                "Check weather forecast"
            ],
            insights: [
                "You usually hike on Saturday mornings.",
                "You bring your dog on outdoor trips."
            ],
            recentHistory: ["Checked weather app"],
            answeredQuestions: ["Q: Do you own a pet? A: Yes"]
        ),
        "Parent Evening": ReminderContext(
            currentDate: Date(),
            currentPlace: "School",
            userName: "Taylor",
            nextUrgentItem: "Pick up kids from soccer practice at 5:30 PM",
            upcomingEvents: [
                "Parent-Teacher Conference at 7:00 PM"
            ],
            pendingReminders: [
                "Bring snacks for the team",
                "Ask teacher about math progress"
            ],
            insights: [
                "You always prepare snacks for soccer practice."
            ],
            recentHistory: ["Left office"],
            answeredQuestions: ["Q: Do you have children? A: Yes"]
        )
    ]
    
    // MARK: - Test Runners
    
    func runReminderDecision(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        print("\n\n====== [TEST: Reminder Decision (\(scenarioName))] ======")
        print("PROMPT TEXT:\n\(context.promptText)\n")
        
        do {
            let decision = try await modelService.decide(from: context)
            print("--- RESULT ---")
            print("Thought Process: \(decision.thoughtProcess)")
            print("Should Notify: \(decision.shouldNotify)")
            print("Category: \(decision.category)")
            print("Title: \(decision.title)")
            print("Body: \(decision.body)")
            print("Follow Up: \(decision.followUpQuestion ?? "None")")
            print("===================================================\n\n")
            
            lastResult = "Decision: \(decision.body)"
        } catch {
            print("Error: \(error)")
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runEventPreparation(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        print("\n\n====== [TEST: Event Preparation (\(scenarioName))] ======")
        
        let promptText = context.nextUrgentItem ?? "No urgent item"
        print("PROMPT TEXT:\n\(promptText)\n")
        
        do {
            let items = try await modelService.suggestPreparation(forPromptText: promptText)
            print("--- RESULT ---")
            print("Items:")
            for item in items {
                print("- \(item)")
            }
            print("===================================================\n\n")
            lastResult = "Prep: \(items.joined(separator: ", "))"
        } catch {
            print("Error: \(error)")
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runInsightExtraction(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        print("\n\n====== [TEST: Insight Extraction (\(scenarioName))] ======")
        print("PROMPT TEXT:\n\(context.promptText)\n")
        
        do {
            let insights = try await modelService.extractInsights(from: context)
            print("--- RESULT ---")
            for insight in insights {
                print("Thought Process: \(insight.thoughtProcess)")
                print("Category: \(insight.category) | Title: \(insight.title)")
                print("Value: \(insight.value) (Confidence: \(insight.confidence))")
                print("Source: \(insight.sourceSummary)")
                print("-")
            }
            if insights.isEmpty {
                print("No insights extracted.")
            }
            print("===================================================\n\n")
            lastResult = "Extracted \(insights.count) insights."
        } catch {
            print("Error: \(error)")
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runOnboardingQuestions(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        print("\n\n====== [TEST: Onboarding Questions (\(scenarioName))] ======")
        print("PROMPT TEXT:\n\(context.promptText)\n")
        
        do {
            let questions = try await modelService.generateOnboardingQuestions(from: context)
            print("--- RESULT ---")
            for q in questions {
                print("[\(q.category)] \(q.question)")
            }
            if questions.isEmpty {
                print("No questions generated. (Model returned empty)")
            }
            print("===================================================\n\n")
            lastResult = "Generated \(questions.count) questions."
        } catch {
            print("Error: \(error)")
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
}
#endif
