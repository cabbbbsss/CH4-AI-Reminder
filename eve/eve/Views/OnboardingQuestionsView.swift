//
//  OnboardingQuestionsView.swift
//  Eve
//
//  Final onboarding step: the model's personalised yes/no questions,
//  shown one card at a time. Answers become QuestionAnswer records that
//  feed every future reminder decision.
//

import SwiftUI
import SwiftData

struct OnboardingQuestionsView: View {
  @Binding var currentStep: Int
  @Environment(\.modelContext) private var modelContext

  @Bindable private var engine = AILearningEngine.shared

  @State private var index = 0
  @State private var answers: [Bool?] = []

  /// Which way we're navigating, so the slide transition matches:
  /// forward = new question enters from the right, back = from the left.
  @State private var goingForward = true

  /// Model-generated questions, or the engine's shared default set as a safety net.
  private var questions: [OnboardingQuestion] {
    engine.onboardingQuestions.isEmpty
      ? AILearningEngine.fallbackQuestions
      : engine.onboardingQuestions
  }

  var body: some View {
    ZStack {
      AuroraBackground()

      VStack(alignment: .leading, spacing: 0) {

        Text("EVE has a few questions to\nrefine your reminders.")
          .font(.eveBody)
          .foregroundStyle(Color.eveOnSurface.opacity(0.55))
          .padding(.top, 100)

        progress
          .padding(.top, Theme.Spacing.xl)

        if let question = questions[safe: index] {

          Text(question.question)
            .font(.eveHeadline)
            .foregroundStyle(Color.eveOnSurface)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Spacing.s)
            .id(index) // re-triggers the transition per question
            .transition(questionTransition)

          VStack(spacing: Theme.Spacing.m) {
            answerButton(title: "Yes", value: true)
            answerButton(title: "No", value: false)
          }
          .padding(.top, Theme.Spacing.xxl)
        }

        Spacer()

        bottomBar
          .padding(.bottom, Theme.Spacing.xxl)
      }
      .padding(.horizontal, Theme.Spacing.gutter)
    }
    // Follows the system appearance like the rest of onboarding, rather than
    // pinning this one step to dark.
    .onAppear {
      // Size the answer store to the question count once.
      if answers.count != questions.count {
        answers = Array(repeating: nil, count: questions.count)
      }
    }
  }

  /// A counter plus a filling track — "3 of 7" alone gave no sense of how
  /// much of onboarding was left at a glance.
  private var progress: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      Text("\(min(index + 1, questions.count)) of \(questions.count)")
        .font(.eveCaption)
        .foregroundStyle(Color.eveOnSurface.opacity(0.4))

      GeometryReader { proxy in
        let fraction = questions.isEmpty
          ? 0
          : CGFloat(index + 1) / CGFloat(questions.count)

        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.eveOnSurface.opacity(0.15))

          Capsule()
            .fill(Color.accentColor)
            .frame(width: proxy.size.width * fraction)
        }
      }
      .frame(height: 4)
      .animation(.easeInOut(duration: 0.25), value: index)
      .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Question \(min(index + 1, questions.count)) of \(questions.count)")
  }

  private var bottomBar: some View {
    HStack {
      if index > 0 {
        Button {
          goingForward = false
          withAnimation(.easeInOut) { index -= 1 }
        } label: {
          Image(systemName: "chevron.left")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.eveOnSurface.opacity(0.8))
        }
        .accessibilityLabel("Previous question")
      }

      Spacer()

      Button {
        complete()
      } label: {
        Text("Skip")
          .font(.eveButton)
          .foregroundStyle(Color.eveOnSurface.opacity(0.8))
      }
    }
  }

  /// Slide direction flips with navigation: forward slides right-to-left,
  /// back slides left-to-right.
  private var questionTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
      removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
    )
  }

  // MARK: - Answer button

  private func answerButton(title: String, value: Bool) -> some View {
    // Both options start neutral; only the chosen one fills in (+ a checkmark),
    // which is what the user sees when they go back to an answered question.
    let isSelected = answers[safe: index].flatMap { $0 } == value

    return Button {
      answer(value)
    } label: {
      Text(title)
        .font(.eveButton)
        .foregroundStyle(isSelected ? .white : Color.eveOnSurface)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        // Pinned to the capsule's leading edge instead of nudged inward with
        // `.padding(.leading, 130)`, which put the tick in a different place
        // relative to the word on every screen width.
        .overlay(alignment: .leading) {
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.eveCaption)
              .foregroundStyle(.white)
              .padding(.leading, Theme.Spacing.l)
          }
        }
        .background {
          Capsule()
            .fill(isSelected ? Color.accentColor : .clear)
            .overlay {
              if !isSelected {
                Capsule().stroke(Color.eveOnSurface.opacity(0.4), lineWidth: 1.5)
              }
            }
        }
    }
    .animation(.easeInOut(duration: 0.2), value: isSelected)
  }

  // MARK: - Flow

  private func answer(_ value: Bool) {
    if answers.indices.contains(index) {
      answers[index] = value
    }

    if index < questions.count - 1 {
      goingForward = true
      withAnimation(.easeInOut) { index += 1 }
    } else {
      complete()
    }
  }

  /// Finishes onboarding: persists answers, enters Home immediately, and
  /// extracts insights in the BACKGROUND so the user never waits on the model.
  ///
  /// The extraction runs in an unstructured Task (not tied to this view's
  /// lifecycle, so it survives navigating away). InsightView is @Query-backed,
  /// so the new beliefs appear there as soon as they're saved.
  private func complete() {

    persistAnswers()

    let context = modelContext
    let place = engine.lastKnownPlace

    Task {
      let assistant = AssistantManager(
        context: context,
        notificationService: NotificationService()
      )
      await assistant.learnInsights(currentPlace: place)
    }

    PermissionManager.shared.completeOnboarding()

    withAnimation { currentStep = 4 }
  }

  /// Writes the answered questions to SwiftData + History. Unanswered are skipped.
  private func persistAnswers() {
    let logger = HistoryLogger(context: modelContext)

    for (question, answer) in zip(questions, answers) {
      guard let answer else { continue }
      let text = answer ? "Yes" : "No"

      modelContext.insert(
        QuestionAnswer(question: question.question, answer: text)
      )

      try? logger.log(.questionAnswered, title: question.question, detail: text)
    }

    try? modelContext.save()
  }
}

/// Safe indexing so an out-of-range access returns nil instead of crashing.
private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

#Preview {
  OnboardingQuestionsView(currentStep: .constant(3))
}
