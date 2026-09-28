//
//  PromptTester.swift
//  Eve
//

import Foundation
import Combine
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.caca.Eve", category: "PromptTester")

struct ExpectedDecision: Codable {
    let shouldNotify: Bool
    let category: String
    let title: String
    let body: String
}

struct MockScenario: Decodable {
    let currentPlace: String?
    let userName: String?
    let nextUrgentItem: String?
    let meetingLink: String?
    let eventDescription: String?
    let eventLocation: String?
    let guests: [String]?
    let upcomingEvents: [String]
    let insights: [String]
    let recentHistory: [String]
    let answeredQuestions: [String]
    let expectedDecision: ExpectedDecision?
    
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
            insights: insights,
            recentHistory: recentHistory,
            answeredQuestions: answeredQuestions,
            contextualPreferences: []
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
    let expectedOutput: String?
    let accuracyScore: Double?
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
    @Published var rawScenarios: [String: MockScenario] = [:]
    @Published var lastAccuracyScore: Double? = nil
    @Published var lastExpectedOutput: String? = nil

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
                self.rawScenarios = decoded
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

    /// Whether the wide context arrived with anything in it.
    ///
    /// NOT a retrieval check, despite the name and the "RAG Active" line it
    /// feeds in the log. Per-event retrieval lives in
    /// `ReminderContextBuilder.buildPreparationContext` and never runs on this
    /// path: `build(currentPlace:)` gathers the user's rows wholesale, and
    /// `MockScenario` hands them over pre-rendered in any case. Read this as
    /// "the scenario had context", and compare free against EVE Plus through
    /// `ReminderContextBuilder.selfCheck()` instead, which exercises the real
    /// retrieval path.
    private func checkRAGUsed(context: ReminderContext) -> Bool {
        return !context.insights.isEmpty || !context.upcomingEvents.isEmpty
    }

    // MARK: - Markdown Logger
    
    private func logToMarkdown(result: TestResult) {
        do {
            let docsUrl = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let mdUrl = docsUrl.appendingPathComponent("test_history.md")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            
            var content = "\n## Test Run: \(dateFormatter.string(from: result.timestamp))\n"
            content += "**Scenario:** \(result.scenarioName) (\(result.testType))\n"
            content += "**RAG Active:** \(result.ragUsed ? "Yes" : "No")\n"
            
            if let accuracy = result.accuracyScore {
                content += "**Accuracy Score:** \(String(format: "%.1f%%", accuracy))\n"
            }
            if let expected = result.expectedOutput {
                content += "\n### Expected Output:\n```\n\(expected)\n```\n"
            }
            content += "\n### Actual Output:\n```\n\(result.output)\n```\n"
            
            if FileManager.default.fileExists(atPath: mdUrl.path) {
                let fileHandle = try FileHandle(forWritingTo: mdUrl)
                fileHandle.seekToEndOfFile()
                if let data = content.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                let header = "# AI Evaluation History\n"
                try (header + content).write(to: mdUrl, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to append markdown log: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Accuracy Scoring
    
    private func calculateAccuracy(real: ReminderDecision, expected: ExpectedDecision) -> Double {
        var score = 0.0
        
        if real.shouldNotify == expected.shouldNotify {
            score += 20.0
        }
        
        if real.category.lowercased() == expected.category.lowercased() {
            score += 10.0
        }
        
        let titleScore = keywordMatchSimilarity(actual: real.title, expected: expected.title)
        score += (titleScore * 20.0)
        
        let bodyScore = keywordMatchSimilarity(actual: real.body, expected: expected.body)
        score += (bodyScore * 50.0)
        
        // Apply a heavy penalty if the core message (the body) is mostly wrong or hallucinated
        if bodyScore < 0.3 {
            score *= 0.5
        }
        
        return score
    }
    
    private func keywordMatchSimilarity(actual: String, expected: String) -> Double {
        let stopWords: Set<String> = ["the", "a", "an", "to", "for", "in", "at", "on", "and", "or", "of", "with", "is", "are", "be", "your", "my", "it", "this", "that"]
        
        func processWords(_ s: String) -> Set<String> {
            let words = s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !stopWords.contains($0) }
                .map { word -> String in
                    var w = word
                    if w.hasSuffix("ing") { w.removeLast(3) }
                    else if w.hasSuffix("ed") { w.removeLast(2) }
                    else if w.hasSuffix("es") && w.count > 3 { w.removeLast(2) }
                    else if w.hasSuffix("s") && w.count > 2 { w.removeLast(1) }
                    return w
                }
            return Set(words)
        }
        
        let actualWords = processWords(actual)
        let expectedWords = processWords(expected)
        
        if expectedWords.isEmpty { return 1.0 }
        
        let intersection = expectedWords.intersection(actualWords).count
        let union = expectedWords.union(actualWords).count
        
        return union == 0 ? 1.0 : Double(intersection) / Double(union)
    }

    // MARK: - Test Runners
    
    func runReminderDecision(scenarioName: String) async {
        guard let context = scenarios[scenarioName] else { return }
        let rawScenario = rawScenarios[scenarioName]
        
        isTesting = true
        defer { isTesting = false }
        
        currentInstructions = modelService.instructions
        currentPromptText = context.promptText
        ragUsed = checkRAGUsed(context: context)
        currentThoughtProcess = ""
        lastAccuracyScore = nil
        lastExpectedOutput = nil
        lastResult = "Generating..."
        
        do {
            let decision = try await modelService.decide(from: context)
            currentThoughtProcess = decision.thoughtProcess
            
            var output = "Should Notify: \(decision.shouldNotify)\n"
            output += "Category: \(decision.category)\n"
            output += "Title: \(decision.title)\n"
            output += "Body: \(decision.body)\n"
            output += "Follow Up: \(decision.followUpQuestion ?? "None")"
            
            var expectedStr: String? = nil
            var accuracy: Double? = nil
            
            if let expected = rawScenario?.expectedDecision {
                expectedStr = "Should Notify: \(expected.shouldNotify)\nCategory: \(expected.category)\nTitle: \(expected.title)\nBody: \(expected.body)"
                accuracy = calculateAccuracy(real: decision, expected: expected)
                lastAccuracyScore = accuracy
                lastExpectedOutput = expectedStr
            }
            
            lastResult = output
            
            let result = TestResult(
                scenarioName: scenarioName,
                testType: "Reminder Decision",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                expectedOutput: expectedStr,
                accuracyScore: accuracy,
                timestamp: Date()
            )
            
            saveResult(result)
            logToMarkdown(result: result)
            
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
    
    /// Runs the real prep pipeline twice over one event — once as a free
    /// account, once as \(SubscriptionService.displayName) — so the difference
    /// retrieval makes is something you can read rather than something the
    /// asserts merely promise.
    ///
    /// This used to hand `suggestPreparation` the scenario's `nextUrgentItem`
    /// string directly, which skipped `ReminderContextBuilder` entirely: no
    /// retrieval, no grounding terms, no gate. It measured the model, not the
    /// feature. It now goes through `buildPreparationContext` and
    /// `OutputGrounding` on exactly the path `CalendarReminderManager` takes.
    ///
    /// Runs against a throwaway store seeded from the scenario's own
    /// `insights`, not the live one.
    ///
    /// This reverses an earlier choice here, for a reason that only appeared
    /// once this became an evaluation rather than a smoke test: the comparison
    /// has to differ by entitlement and nothing else, and a live store makes
    /// the belief half vary per install. Worse, on a fresh test device that
    /// store is *empty* — so the belief half of retrieval has never actually
    /// run, and every result so far has really only exercised the corpus.
    func runEventPreparation(scenarioName: String) async {
        guard let scenario = rawScenarios[scenarioName] else { return }

        isTesting = true
        defer { isTesting = false }

        guard let container = try? ModelContainer(
            for: AIInsight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            lastResult = "Could not open an in-memory store for the comparison."
            return
        }

        let modelContext = ModelContext(container)

        // Titles are deliberately neutral. `relevantInsights` matches on
        // "title: value", so a descriptive title would add terms of its own and
        // quietly decide the retrieval this test exists to measure.
        for (index, value) in scenario.insights.enumerated() {
            modelContext.insert(
                AIInsight(
                    category: .behavior,
                    title: "Belief \(index + 1)",
                    value: value,
                    confidence: 0.8,
                    sourceSummary: "Seeded by PromptTester"
                )
            )
        }

        // "Board Meeting at 2:00 PM" -> "Board Meeting". Every scenario carries
        // the time in that string; the whole string is a serviceable title for
        // one that doesn't.
        let title = scenario.nextUrgentItem?
            .components(separatedBy: " at ").first?
            .trimmingCharacters(in: .whitespaces) ?? scenarioName

        let date = Date.now.addingTimeInterval(3600)

        currentInstructions = "Event Preparation (strict) — free vs \(SubscriptionService.displayName)"
        currentThoughtProcess = "N/A — EventPreparation carries no scratchpad field"
        ragUsed = false
        lastResult = "Generating..."

        var output = ""
        var prompts = ""

        for isPro in [false, true] {

            let label = isPro ? SubscriptionService.displayName : "Free"

            guard let prompt = ReminderContextBuilder(
                context: modelContext,
                personalizedRetrieval: isPro
            ).buildPreparationContext(
                eventTitle: title,
                eventDate: date,
                eventNotes: scenario.eventDescription,
                eventLocation: scenario.eventLocation,
                eventAttendees: scenario.guests?.joined(separator: ", "),
                eventMeetingURL: scenario.meetingLink
            ) else {
                output += "\n===== \(label) =====\nBuilder declined this event (language filter).\n"
                continue
            }

            prompts += "===== \(label) =====\n\(prompt.promptText)\n\n"

            let items = (try? await modelService.suggestPreparation(
                forPromptText: prompt.promptText
            )) ?? []

            // The same gate, fed the same way `CalendarReminderManager` feeds
            // it — including the empty set that an unmatched event earns, so a
            // bypass here means a bypass in the app.
            let result = OutputGrounding.filter(
                items,
                groundedIn: prompt.retrievalMissed ? [] : prompt.groundingTerms,
                notRestating: prompt.subjectTerms
            )

            let retrieval = isPro
                ? (prompt.retrievalMissed ? "ran, matched nothing" : "matched")
                : "off (free)"


            output += "\n===== \(label) =====\n"
            output += "Retrieval: \(retrieval)\n"
            output += "Model returned \(items.count), shown \(result.kept.count)\n"
            output += result.kept.isEmpty
                ? "- (nothing)\n"
                : result.kept.map { "- \($0)\n" }.joined()

            if !result.dropped.isEmpty {
                output += "Dropped as ungrounded:\n"
                output += result.dropped.map { "- \($0)\n" }.joined()
            }

            // Which seeded beliefs survived matching, named individually: the
            // prompt shows what got through, this shows what was on offer, and
            // the gap between them is the retrieval result. Written here, after
            // the section header — appending it where the values are computed
            // filed the whole block under the previous tier.
            if isPro {
                let retrieved = scenario.insights.filter { prompt.promptText.contains($0) }
                output += "Beliefs offered \(scenario.insights.count), retrieved \(retrieved.count)\n"
                for belief in scenario.insights {
                    output += "  \(retrieved.contains(belief) ? "[hit] " : "[miss]") \(belief)\n"
                }
            }

            if isPro, !prompt.retrievalMissed { ragUsed = true }

        }

        currentPromptText = prompts
        lastResult = output

        // No do/catch: both model calls above already absorb their failure as
        // an empty item list, which the report shows as "returned 0".
        let result = TestResult(
            scenarioName: scenarioName,
            testType: "Event Preparation (free vs Plus)",
            ragUsed: ragUsed,
            promptInstructions: currentInstructions,
            promptText: currentPromptText,
            thoughtProcess: currentThoughtProcess,
            output: output,
            expectedOutput: nil,
            accuracyScore: nil,
            timestamp: Date()
        )
        saveResult(result)
        logToMarkdown(result: result)
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
            
            let result = TestResult(
                scenarioName: scenarioName,
                testType: "Insight Extraction",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                expectedOutput: nil,
                accuracyScore: nil,
                timestamp: Date()
            )
            saveResult(result)
            logToMarkdown(result: result)
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
            
            let result = TestResult(
                scenarioName: scenarioName,
                testType: "Onboarding Questions",
                ragUsed: ragUsed,
                promptInstructions: currentInstructions,
                promptText: currentPromptText,
                thoughtProcess: currentThoughtProcess,
                output: output,
                expectedOutput: nil,
                accuracyScore: nil,
                timestamp: Date()
            )
            saveResult(result)
            logToMarkdown(result: result)
        } catch {
            lastResult = "Error: \(error.localizedDescription)"
        }
    }
}
#endif
