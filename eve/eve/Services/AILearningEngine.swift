import Foundation
import SwiftData
import Observation
import FoundationModels

/// One finished step in the onboarding learning log.
/// `succeeded == false` means the step ran but found nothing to work with
/// (e.g. the relevant permission wasn't granted) — shown as an ✗ instead of ✓.
struct LearningStep: Identifiable {
  let id = UUID()
  let text: String
  let succeeded: Bool
}

/// Drives the onboarding "learning" screen.
///
/// This runs the REAL pipeline — it imports Calendar & Reminders into
/// SwiftData, detects the current place, then asks the Foundation Model
/// to summarise first insights — while exposing streaming progress
/// (currentAnalysisTask / completedSteps) for AILearningView.
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
  var completedSteps: [LearningStep] = []

  /// Questions the onboarding questions screen will ask, produced by the
  /// model at the end of the learning pass (falls back to a default set).
  var onboardingQuestions: [OnboardingQuestion] = []

  /// The place detected during the learning pass, reused when the
  /// questions screen refines insights at the end of onboarding.
  private(set) var lastKnownPlace: String?

  /// A safe default set used when the model can't generate questions.
  /// Shared with OnboardingQuestionsView as its default set too.
  static let fallbackQuestions: [OnboardingQuestion] = [
    OnboardingQuestion(question: "Do you take any medication on a regular schedule?", category: "health"),
    OnboardingQuestion(question: "Do you have a pet that needs regular care?", category: "pet"),
    OnboardingQuestion(question: "Do you commute to a workplace on weekdays?", category: "commute"),
    OnboardingQuestion(question: "Do you exercise or go to the gym regularly?", category: "routine"),
    OnboardingQuestion(question: "Would you like reminders before you leave home?", category: "preference")
  ]

  func analyzeUserRoutines(context: ModelContext?) async {

    isAnalyzing = true
    analysisProgress = 0.0
    completedSteps = []
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
    //    Succeeds if at least one of the two was granted — that's still data.
    await runStep("Importing your Calendar & Reminders…", progress: 0.3) {
      await sync.start()
      return sync.hasCalendarAccess == true || sync.hasReminderAccess == true
    }

    // 2. Establish where the user is right now. Succeeds if location is allowed.
    await runStep("Detecting your location…", progress: 0.55) {
      await location.start()
      return !location.accessDenied
    }

    lastKnownPlace = location.currentPlace

    // 3. Let the Foundation Model summarise first insights (no notification).
    //    Routines come from schedule data, so this needs calendar OR reminders.
    //    Location alone isn't enough — that step is marked ✗ (but location still
    //    enriches the learning when calendar/reminders are also available).
    await runStep("Learning your routines…", progress: 0.8) {
      let hasRoutineData = sync.hasCalendarAccess == true || sync.hasReminderAccess == true
      if hasRoutineData {
        // Extract durable beliefs from the imported calendar/reminders,
        // not a reminder decision — so learning actually produces insights.
        await assistant.learnInsights(currentPlace: location.currentPlace)
      }
      return hasRoutineData
    }

    // 4. Prepare personalised questions. This ALWAYS succeeds: with data the
    //    questions confirm patterns; without data they gather what the model
    //    still needs to know about the user.
    await runStep("Preparing a few questions…", progress: 1.0) {
      let generated = await assistant.onboardingQuestions(
        currentPlace: location.currentPlace
      )
      self.onboardingQuestions = generated.isEmpty ? Self.fallbackQuestions : generated
      return true
    }
  }

  /// Marks a step active, awaits its work, then records the outcome —
  /// producing the streaming checklist the onboarding screen renders.
  /// The work closure returns whether the step actually had data to act on.
  private func runStep(
    _ task: String,
    progress: Double,
    _ work: () async -> Bool
  ) async {
    currentAnalysisTask = task
    let succeeded = await work()
    analysisProgress = progress
    completedSteps.append(LearningStep(text: task, succeeded: succeeded))
  }
}
