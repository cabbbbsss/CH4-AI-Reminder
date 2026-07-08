import Foundation
import SwiftData
import NaturalLanguage
import Observation
import FoundationModels

@Observable
final class AILearningEngine {
  static let shared = AILearningEngine()

  /// True when the on-device Foundation Model is ready to use.
  /// False when Apple Intelligence is disabled, still downloading,
  /// or unsupported on this device.
  var isAppleIntelligenceAvailable: Bool {
    if case .available = SystemLanguageModel.default.availability {
      return true
    }
    return false
  }

  var isAnalyzing: Bool = false
  var analysisProgress: Double = 0.0
  var currentAnalysisTask: String = ""

  /// Steps that have finished, in order — drives the streaming log UI.
  var completedTasks: [String] = []

  var predictedActivities: [Prediction] = []
  var suggestedQuestions: [String] = []

  func analyzeUserRoutines(context: ModelContext?) async {
    let steps: [(task: String, progress: Double)] = [
      ("Loading Calendar & Reminders History...", 0.25),
      ("Processing Location Patterns...", 0.5),
      ("Learning Your Daily Routines...", 0.75),
      ("Generating Contextual Predictions...", 1.0)
    ]

    await MainActor.run {
      self.isAnalyzing = true
      self.analysisProgress = 0.0
      self.completedTasks = []
    }

    // Simulating Apple Intelligence Foundation Model processing
    for step in steps {
      await MainActor.run {
        self.currentAnalysisTask = step.task
      }

      try? await Task.sleep(nanoseconds: 1_500_000_000)

      await MainActor.run {
        self.analysisProgress = step.progress
        self.completedTasks.append(step.task)
      }
    }

    await MainActor.run {
      self.generateMockPredictions()
      self.isAnalyzing = false
    }
  }
  
  private func generateMockPredictions() {
    predictedActivities = [
      Prediction(suggestion: "Skip tomorrow's work alarm", context: "Tomorrow is a public holiday.", type: .scheduleChange, confidence: 95.0),
      Prediction(suggestion: "Bring your umbrella", context: "Your meeting at 3 PM is outside.", type: .insight, confidence: 88.0),
      Prediction(suggestion: "Don't forget your office badge", context: "You usually leave for work around this time.", type: .reminder, confidence: 92.0)
    ]
    
    suggestedQuestions = [
      "Do you take medication regularly?",
      "Has your gym schedule changed recently?",
      "Would you like automatic reminders for vitamins?"
    ]
  }
}
