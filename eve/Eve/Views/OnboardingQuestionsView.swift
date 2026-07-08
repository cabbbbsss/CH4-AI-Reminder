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
  @State private var isFinishing = false

  /// Model-generated questions, or a small default set as a safety net.
  private var questions: [OnboardingQuestion] {
    engine.onboardingQuestions.isEmpty ? defaultQuestions : engine.onboardingQuestions
  }

  private var defaultQuestions: [OnboardingQuestion] {
    [
      OnboardingQuestion(question: "Do you take any medication on a regular schedule?", category: "health"),
      OnboardingQuestion(question: "Do you have a pet that needs regular care?", category: "pet"),
      OnboardingQuestion(question: "Do you commute to a workplace on weekdays?", category: "commute")
    ]
  }

  var body: some View {
    ZStack {
      background

      VStack(alignment: .leading, spacing: 0) {

        // Subtitle
        Text("EVE has a few questions to\nrefine your reminders.")
          .font(.system(size: 17, weight: .regular))
          .foregroundColor(Color(hex: "#1D3557").opacity(0.55))
          .padding(.top, 120)

        // Progress
        Text("\(min(index + 1, questions.count)) of \(questions.count)")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(hex: "#1D3557").opacity(0.4))
          .padding(.top, 24)

        if let question = questions[safe: index] {

          // Question text
          Text(question.question)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(Color(hex: "#1D3557"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .id(index) // re-triggers the transition per question
            .transition(.asymmetric(
              insertion: .move(edge: .trailing).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            ))

          // Answers
          VStack(spacing: 16) {
            answerButton(title: "Yes", value: true)
            answerButton(title: "No", value: false)
          }
          .padding(.top, 28)
        }

        Spacer()

        // Back chevron
        HStack {
          Spacer()
          if index > 0 {
            Button {
              withAnimation(.easeInOut) { index -= 1 }
            } label: {
              Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(hex: "#E0ECF7").opacity(0.7))
            }
          }
        }
        .padding(.bottom, 40)
      }
      .padding(.horizontal, 36)

      if isFinishing {
        Color.black.opacity(0.15).ignoresSafeArea()
        ProgressView()
          .tint(.white)
          .scaleEffect(1.4)
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      // Size the answer store to the question count once.
      if answers.count != questions.count {
        answers = Array(repeating: nil, count: questions.count)
      }
    }
  }

  // MARK: - Answer button

  private func answerButton(title: String, value: Bool) -> some View {
    let isSelected = answers[safe: index].flatMap { $0 } == value

    return Button {
      answer(value)
    } label: {
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundColor(isSelected || value ? .white : Color(hex: "#1D3557"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background {
          if value {
            Capsule().fill(Color(hex: "#3B8FCB"))
          } else {
            Capsule()
              .fill(isSelected ? Color(hex: "#3B8FCB") : Color.clear)
              .overlay(
                Capsule().stroke(Color(hex: "#1D3557").opacity(0.4), lineWidth: 1.5)
              )
          }
        }
    }
    .disabled(isFinishing)
  }

  // MARK: - Flow

  private func answer(_ value: Bool) {
    if answers.indices.contains(index) {
      answers[index] = value
    }

    if index < questions.count - 1 {
      withAnimation(.easeInOut) { index += 1 }
    } else {
      Task { await finish() }
    }
  }

  /// Persists every answer, folds them into insights, and enters Home.
  private func finish() async {

    isFinishing = true

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

    // Now that Eve knows the answers, refine insights (no notification yet).
    let assistant = AssistantManager(
      context: modelContext,
      notificationService: NotificationService()
    )
    await assistant.generateInitialInsights(currentPlace: engine.lastKnownPlace)

    PermissionManager.shared.completeOnboarding()

    isFinishing = false

    withAnimation { currentStep = 4 }
  }

  // MARK: - Background

  private var background: some View {
    LinearGradient(
      stops: [
        .init(color: Color(hex: "#E4EDF6"), location: 0.0),
        .init(color: Color(hex: "#B9CADD"), location: 0.35),
        .init(color: Color(hex: "#5F7FA4"), location: 0.7),
        .init(color: Color(hex: "#1D3557"), location: 1.0)
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
