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
      background

      VStack(alignment: .leading, spacing: 0) {

        // Subtitle
        Text("EVE has a few questions to\nrefine your reminders.")
          .font(.system(size: 17, weight: .regular))
          .foregroundColor(Color(.textSecondary).opacity(0.55))
          .padding(.top, 120)

        // Progress
        Text("\(min(index + 1, questions.count)) of \(questions.count)")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(.textSecondary).opacity(0.4))
          .padding(.top, 24)

        if let question = questions[safe: index] {

          // Question text
          Text(question.question)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(Color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .id(index) // re-triggers the transition per question
            .transition(questionTransition)

          // Answers
          VStack(spacing: 16) {
            answerButton(title: "Yes", value: true)
            answerButton(title: "No", value: false)
          }
          .padding(.top, 28)
        }

        Spacer()

        // Bottom bar: back chevron on the left.
        HStack {
          if index > 0 {
            Button {
              goingForward = false
              withAnimation(.easeInOut) { index -= 1 }
            } label: {
              Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(.textPrimary).opacity(0.8))
            }
          }

          Spacer()

          Button {
            complete()
          } label: {
            Text("Skip")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(Color(.textPrimary).opacity(0.8))
          }
        }
        .padding(.bottom, 40)
      }
      .padding(.horizontal, 36)
    }
    .preferredColorScheme(.dark)
    .onAppear {
      // Size the answer store to the question count once.
      if answers.count != questions.count {
        answers = Array(repeating: nil, count: questions.count)
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
    // Both options start neutral; only the chosen one turns blue (+ a checkmark),
    // which is what the user sees when they go back to an answered question.
    let isSelected = answers[safe: index].flatMap { $0 } == value

    return Button {
      answer(value)
    } label: {
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundColor(isSelected ? .white : Color(.textSecondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .overlay(alignment: .leading) {
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .bold))
              .foregroundColor(.white)
              .padding(.leading, 130)
          }
        }
        .background {
          Capsule()
            .fill(isSelected ? Color.accentColor : Color.clear)
            .overlay {
              if !isSelected {
                Capsule().stroke(Color(.textSecondary).opacity(0.4), lineWidth: 1.5)
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

  // MARK: - Background

  private var background: some View {
    LinearGradient(
      stops: [
        .init(color: Color(.gradientSecondaryStart), location: 0.0),
        .init(color: Color(.gradientSecondaryStart), location: 0.35),
        .init(color: Color(.textTertiary), location: 0.7),
        .init(color: Color(.gradientPrimaryStart), location: 1.0)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
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
