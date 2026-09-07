//
//  PromptTester.swift
//  Eve
//

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.caca.Eve", category: "PromptTester")

struct MockScenario: Decodable {
    let currentPlace: String?
    let userName: String?
    let nextUrgentItem: String?
    let meetingLink: String?
    let eventDescription: String?
    let eventLocation: String?
    let guests: [String]?
    let upcomingEvents: [String]
    let pendingReminders: [String]
    let insights: [String]
    let recentHistory: [String]
    let answeredQuestions: [String]
    
    var context: ReminderContext {
        ReminderContext(
            currentDate: Date(),
            currentPlace: currentPlace,
            userName: userName,
            nextUrgentItem: nextUrgentItem,
            meetingLink: meetingLink,
            eventDescription: eventDescription,
            eventLocation: eventLocation,
            guests: guests,
            upcomingEvents: upcomingEvents,
            pendingReminders: pendingReminders,
            insights: insights,
            recentHistory: recentHistory,
            answeredQuestions: answeredQuestions
        )
    }
}

struct TestResult: Codable {
    let scenarioName: String
    let testType: String
    let ragUsed: Bool
    let promptInstructions: String
    let promptText: String
    let thoughtProcess: String
    let output: String
    let timestamp: Date
}

#if DEBUG
@MainActor
final class PromptTester: ObservableObject {
    let modelService = FoundationModelService()
    
    @Published var isTesting = false
    @Published var lastResult: String = ""
    @Published var currentPromptText: String = ""
    @Published var currentInstructions: String = ""
    @Published var currentThoughtProcess: String = ""
    @Published var ragUsed: Bool = false
    @Published var scenarios: [String: ReminderContext] = [:]

    init() {
        loadScenarios()
    }
    
    private func loadScenarios() {
        if let bundleURL = Bundle.main.url(forResource: "mock_scenarios", withExtension: "json") {
            do {
                let data = try Data(contentsOf: bundleURL)
                let decoded = try JSONDecoder().decode([String: MockScenario].self, from: data)
                var loadedScenarios = [String: ReminderContext]()
                for (key, value) in decoded {
                    loadedScenarios[key] = value.context
                }
                self.scenarios = loadedScenarios
                logger.info("Loaded \(loadedScenarios.count) mock scenarios from bundle.")
            } catch {
                logger.error("Failed to decode mock scenarios: \(error.localizedDescription)")
            }
        } else {
            logger.error("mock_scenarios.json not found in main bundle.")
        }
    }
    
    private func saveResult(_ result: TestResult) {
        do {
            let docsUrl = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let resultsUrl = docsUrl.appendingPathComponent("test_results.json")
            
            var existingResults: [TestResult] = []
            if let data = try? Data(contentsOf: resultsUrl) {
                existingResults = (try? JSONDecoder().decode([TestResult].self, from: data)) ?? []
            }
            
            existingResults.append(result)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(existingResults)
            try encoded.write(to: resultsUrl, options: .atomic)
            
            logger.info("Saved test result to: \(resultsUrl.path)")
            print("Saved test result to: \(resultsUrl.path)")
        } catch {
            logger.error("Failed to save test result: \(error.localizedDescription)")
        }
    }

    private func checkRAGUsed(context: ReminderContext) -> Bool {
        // RAG is effectively considered "used" if there are any retrieved insights, upcoming events, or pending reminders injected.
        return !context.insights.isEmpty || !context.upcomingEvents.isEmpty || !context.pendingReminders.isEmpty
    }

    // MARK: - Test Runners
    
    func runReminderDecision(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        currentInstructions = modelService.instructions
        currentPromptText = context.promptText
        ragUsed = checkRAGUsed(context: context)
        currentThoughtProcess = ""
        lastResult = "Generating..."
        
        do {
            let decision = try await modelService.decide(from: context)
            currentThoughtProcess = decision.thoughtProcess
            
            var output = "Should Notify: \(decision.shouldNotify)\n"
            output += "Category: \(decision.category)\n"
            output += "Title: \(decision.title)\n"
            output += "Body: \(decision.body)\n"
            output += "Follow Up: \(decision.followUpQuestion ?? "None")"
            
            lastResult = output
            
            saveResult(TestResult(
                scenarioName: scenarioName,
                testType: "Reminder Decision",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                timestamp: Date()
            ))
            
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runEventPreparation(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        let promptText = context.nextUrgentItem ?? "No urgent item"
        currentInstructions = "Event Preparation Instructions (Internal strictly guided array schema)"
        currentPromptText = promptText
        ragUsed = false // Event prep test here doesn't use the full RAG builder pipeline for brevity
        currentThoughtProcess = "N/A for Event Preparation Array Schema"
        lastResult = "Generating..."
        
        do {
            let items = try await modelService.suggestPreparation(forPromptText: promptText)
            var output = "Items:\n"
            for item in items {
                output += "- \(item)\n"
            }
            if items.isEmpty {
                output += "No preparation needed."
            }
            lastResult = output
            
            saveResult(TestResult(
                scenarioName: scenarioName,
                testType: "Event Preparation",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                timestamp: Date()
            ))
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runInsightExtraction(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        currentInstructions = modelService.insightExtractionInstructions
        currentPromptText = context.promptText
        ragUsed = checkRAGUsed(context: context)
        currentThoughtProcess = ""
        lastResult = "Generating..."
        
        do {
            let insights = try await modelService.extractInsights(from: context)
            // Note: Since extractInsights returns [AIInsight], we don't have direct access to thoughtProcess here
            // unless we change the return type in FoundationModelService to expose InsightExtraction.
            currentThoughtProcess = "Scratchpad used internally by InsightExtraction (Not exposed in final [AIInsight])"
            
            var output = ""
            for insight in insights {
                output += "[\(insight.category)] \(insight.title): \(insight.value)\n"
            }
            if insights.isEmpty {
                output += "No insights extracted."
            }
            lastResult = output
            
            saveResult(TestResult(
                scenarioName: scenarioName,
                testType: "Insight Extraction",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                timestamp: Date()
            ))
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    func runOnboardingQuestions(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        
        isTesting = true
        defer { isTesting = false }
        
        currentInstructions = modelService.onboardingInstructions
        currentPromptText = context.promptText
        ragUsed = checkRAGUsed(context: context)
        currentThoughtProcess = ""
        lastResult = "Generating..."
        
        do {
            let questions = try await modelService.generateOnboardingQuestions(from: context)
            currentThoughtProcess = "Scratchpad used internally (Not exposed in final [OnboardingQuestion])"
            
            var output = ""
            for q in questions {
                output += "[\(q.category)] \(q.question)\n"
            }
            if questions.isEmpty {
                output += "No questions generated. (Model returned empty)"
            }
            lastResult = output
            
            saveResult(TestResult(
                scenarioName: scenarioName,
                testType: "Onboarding Questions",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                timestamp: Date()
            ))
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
}
#endif
