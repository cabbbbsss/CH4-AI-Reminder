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
  /// The quieter second line under the step. While a step is in flight this
  /// says what Eve is doing; once it lands it is replaced by what she
  /// actually found, so the finished log reports results rather than
  /// repeating the promise.
  let detail: String
  let succeeded: Bool
}

/// Drives the onboarding "learning" screen.
///
/// This runs the REAL pipeline — it imports the Calendar into SwiftData,
/// then asks the Foundation Model to summarise first insights — while
/// exposing streaming progress (currentAnalysisTask / completedSteps)
/// for AILearningView.
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

  /// The second line shown under the in-flight step.
  var currentAnalysisDetail: String = ""

  /// Steps that have finished, in order — drives the streaming log UI.
  var completedSteps: [LearningStep] = []

  /// Questions the onboarding questions screen will ask, produced by the
  /// model at the end of the learning pass (falls back to a default set).
  var onboardingQuestions: [OnboardingQuestion] = []

  /// The last place Eve detected, reused when the questions screen refines
  /// insights at the end of onboarding.
  ///
  /// Stays nil through onboarding now that location isn't requested there —
  /// it only fills in once the user grants location from the Locations tab.
  /// Every consumer takes it as an optional.
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

  /// What a step reports back: whether it had anything to work with, and the
  /// line to show underneath it once it's finished.
  private struct StepOutcome {
    let succeeded: Bool
    let detail: String
  }

  /// "1 event" / "36 events". A bare interpolation gives "1 events", which is
  /// exactly the kind of small wrongness that makes a screen feel unfinished.
  private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }

  func analyzeUserRoutines(context: ModelContext?) async {

    isAnalyzing = true
    analysisProgress = 0.0
    completedSteps = []
    currentAnalysisTask = ""
    currentAnalysisDetail = ""

    defer { isAnalyzing = false }

    guard let context else {
      // No store to learn from — nothing to import. Finish cleanly.
      analysisProgress = 1.0
      return
    }

    // The same managers HomeView uses; here they run once, up front.
    //
    // No LocationActivityManager: onboarding asks for Calendar and nothing
    // else, and starting the location manager here would fire the system
    // location prompt — the thing moving it out of onboarding was meant to
    // avoid. Location is requested from the Locations tab instead.
    let notifications = NotificationService.shared
    let sync = EventKitSyncManager(context: context)
    let assistant = AssistantManager(
      context: context,
      notificationService: notifications
    )

    // 1. Ask EventKit for access. Its own step, so a refusal reads as
    //    "we couldn't connect" rather than "your calendar is empty".
    await runStep(
      "Connecting to your calendar…",
      running: "Checking Eve can read your events",
      progress: 0.25
    ) {
      let granted = await sync.requestAccess()

      return StepOutcome(
        succeeded: granted,
        detail: granted
          ? "Eve can read your schedule"
          : "Calendar access is off — you can turn it on in Settings"
      )
    }

    // 2. Pull the user's real Calendar into SwiftData.
    await runStep(
      "Reading your calendar…",
      running: "Looking through the past few weeks",
      progress: 0.5
    ) {
      guard sync.hasCalendarAccess == true else {
        return StepOutcome(
          succeeded: false,
          detail: "Skipped — there's no calendar to read yet"
        )
      }

      await sync.beginSyncing()

      let events = (try? context.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0

      return StepOutcome(
        succeeded: true,
        detail: events == 0
          ? "Your calendar is clear for now — Eve will catch up later"
          : "Found \(Self.counted(events, "event", "events")) to learn from"
      )
    }

    // 3. Let the Foundation Model summarise first insights (no notification).
    //    Routines come from schedule data, so this needs the calendar.
    await runStep(
      "Learning your routines…",
      running: "Working out what repeats each week",
      progress: 0.75
    ) {
      guard sync.hasCalendarAccess == true else {
        return StepOutcome(
          succeeded: false,
          detail: "Needs your calendar before it can spot a pattern"
        )
      }

      // Counted around the call, so the line reports what this pass actually
      // learned rather than everything Eve has ever believed.
      let before = (try? context.fetchCount(FetchDescriptor<AIInsight>())) ?? 0

      // Extract durable beliefs from the imported calendar, not a reminder
      // decision — so learning actually produces insights.
      await assistant.learnInsights(currentPlace: lastKnownPlace)

      let learned = max(0, ((try? context.fetchCount(FetchDescriptor<AIInsight>())) ?? 0) - before)

      return StepOutcome(
        succeeded: true,
        detail: learned == 0
          ? "No clear pattern yet — give it time"
          : "Picked up \(Self.counted(learned, "thing", "things")) about your week"
      )
    }

    // 4. Prepare personalised questions. This ALWAYS succeeds: with data the
    //    questions confirm patterns; without data they gather what the model
    //    still needs to know about the user.
    await runStep(
      "Preparing a few questions…",
      running: "Deciding what's still worth asking",
      progress: 1.0
    ) {
      let generated = await assistant.onboardingQuestions(
        currentPlace: lastKnownPlace
      )
      self.onboardingQuestions = generated.isEmpty ? Self.fallbackQuestions : generated

      return StepOutcome(
        succeeded: true,
        detail: "\(Self.counted(self.onboardingQuestions.count, "question", "questions")) ready for you"
      )
    }
  }

  /// Marks a step active, awaits its work, then records the outcome —
  /// producing the streaming checklist the onboarding screen renders.
  ///
  /// `running` is shown while the step is in flight; the outcome's own detail
  /// replaces it once the step lands, so a finished row says what was found
  /// instead of restating what was about to happen.
  private func runStep(
    _ task: String,
    running: String,
    progress: Double,
    _ work: () async -> StepOutcome
  ) async {
    currentAnalysisTask = task
    currentAnalysisDetail = running
    let outcome = await work()
    analysisProgress = progress
    completedSteps.append(
      LearningStep(text: task, detail: outcome.detail, succeeded: outcome.succeeded)
    )
  }
}
