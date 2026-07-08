import Foundation
import SwiftData
import Observation
import FoundationModels

/// Drives the onboarding "learning" screen.
///
/// This runs the REAL pipeline — it imports Calendar & Reminders into
/// SwiftData, detects the current place, then asks the Foundation Model
/// to summarise first insights — while exposing streaming progress
/// (currentAnalysisTask / completedTasks) for AILearningView.
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

  func analyzeUserRoutines(context: ModelContext?) async {

    isAnalyzing = true
    analysisProgress = 0.0
    completedTasks = []
    currentAnalysisTask = ""

    defer { isAnalyzing = false }

    guard let context else {
      // No store to learn from — nothing to import. Finish cleanly.
      analysisProgress = 1.0
      return
    }

    // The same managers HomeView uses; here they run once, up front.
    let notifications = NotificationService()
    let sync = EventKitSyncManager(context: context)
    let location = LocationActivityManager(context: context)
    let assistant = AssistantManager(
      context: context,
      notificationService: notifications
    )

    // 1. Pull the user's real Calendar & Reminders into SwiftData.
    await runStep("Importing your Calendar & Reminders…", progress: 0.3) {
      await sync.start()
    }

    // 2. Establish where the user is right now.
    await runStep("Detecting your location…", progress: 0.55) {
      await location.start()
    }

    // 3. Let the Foundation Model summarise first insights (no notification).
    await runStep("Learning your routines…", progress: 0.85) {
      await assistant.generateInitialInsights(currentPlace: location.currentPlace)
    }

    // 4. Settle.
    await runStep("Generating contextual insights…", progress: 1.0) {}
  }

  /// Marks a step active, awaits its work, then marks it complete —
  /// producing the streaming checklist the onboarding screen renders.
  private func runStep(
    _ task: String,
    progress: Double,
    _ work: () async -> Void
  ) async {
    currentAnalysisTask = task
    await work()
    analysisProgress = progress
    completedTasks.append(task)
  }
}
