import SwiftUI
import SwiftData
import UIKit

struct AILearningView: View {
  @Bindable var engine = AILearningEngine.shared
  @Binding var currentStep: Int
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL

  @State private var isFloating = false
  @State private var aiMissing = false
  @State private var hasStartedAnalysis = false

  private var isFinished: Bool {
    !engine.isAnalyzing && engine.analysisProgress >= 1.0
  }

  var body: some View {
    ZStack {
      background

      VStack(spacing: 0) {
        mascotCluster
          .padding(.top, 16)

        Text(headline)
          .font(.system(size: 32, weight: .bold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .animation(.easeInOut, value: isFinished)
          .animation(.easeInOut, value: aiMissing)

        if aiMissing {

          missingAICard
            .padding(.top, 32)

        } else {

          learningLog
            .padding(.top, 36)
            .padding(.horizontal, 44)

        }

        Spacer(minLength: 0)

        if isFinished {
          continueButton
        }
      }
    }
    .preferredColorScheme(.dark)
    .task {
      await startIfPossible()
    }
    .onChange(of: scenePhase) { _, newPhase in
      // The user may have gone to Settings to enable Apple
      // Intelligence — re-check whenever we become active again.
      if newPhase == .active {
        Task { await startIfPossible() }
      }
    }
  }

  private var headline: String {
    if aiMissing {
      return "EVE AI Routine\nLearning is Paused"
    }
    return isFinished
      ? "EVE has learned\nyour routine!"
      : "EVE is ingesting\nyour data..."
  }

  private func startIfPossible() async {

    aiMissing = !engine.isAppleIntelligenceAvailable

    guard !aiMissing, !hasStartedAnalysis else { return }

    hasStartedAnalysis = true

    await engine.analyzeUserRoutines(context: modelContext)

  }

  // MARK: - Background

  private var background: some View {
    LinearGradient(
      stops: [
        .init(color: Color(hex: "#16273F"), location: 0.0),
        .init(color: Color(hex: "#1D3557"), location: 0.35),
        .init(color: Color(hex: "#5F7FA4"), location: 0.75),
        .init(color: Color(hex: "#DCE8F4"), location: 1.0)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }

  // MARK: - Mascot + floating data sources

  private var mascotCluster: some View {
    ZStack {
      GlassIconTile(systemName: "calendar", rotation: -14)
        .offset(x: -125, y: -95)
        .offset(y: isFloating ? -6 : 6)
        .animation(
          .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
          value: isFloating
        )

      GlassIconTile(systemName: "location.fill", rotation: 12)
        .offset(x: 105, y: -115)
        .offset(y: isFloating ? 6 : -6)
        .animation(
          .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
          value: isFloating
        )

      GlassIconTile(systemName: "clock", rotation: -10, size: 58)
        .offset(x: -145, y: 15)
        .offset(y: isFloating ? -5 : 5)
        .animation(
          .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
          value: isFloating
        )

      GlassIconTile(systemName: "checklist", rotation: 10, size: 58)
        .offset(x: 140, y: 20)
        .offset(y: isFloating ? 5 : -5)
        .animation(
          .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
          value: isFloating
        )

      ThoughtBubble()
        .offset(x: 122, y: -62)
        .offset(y: isFloating ? -4 : 4)
        .animation(
          .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
          value: isFloating
        )

      Image("Avatar")
        .resizable()
        .scaledToFit()
        .frame(width: 190, height: 190)
        .scaleEffect(isFloating ? 1.03 : 0.97)
        .animation(
          .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
          value: isFloating
        )
    }
    .frame(height: 330)
    .onAppear {
      isFloating = true
    }
  }

  // MARK: - Streaming log

  private var learningLog: some View {
    VStack(alignment: .leading, spacing: 0) {

      ForEach(Array(engine.completedTasks.enumerated()), id: \.offset) { index, task in
        LearningLogRow(
          icon: "checkmark",
          text: task,
          isActive: false,
          isLast: !engine.isAnalyzing && index == engine.completedTasks.count - 1
        )
      }

      if engine.isAnalyzing {
        LearningLogRow(
          icon: "ellipsis",
          text: engine.currentAnalysisTask.isEmpty
            ? "Processing..."
            : engine.currentAnalysisTask,
          isActive: true,
          isLast: true
        )
      }

    }
    .animation(
      .spring(response: 0.5, dampingFraction: 0.8),
      value: engine.completedTasks.count
    )
  }

  // MARK: - Missing Apple Intelligence

  private var missingAICard: some View {
    HStack(alignment: .center, spacing: 16) {

      Image(systemName: "apple.intelligence")
        .font(.system(size: 40, weight: .regular))
        .foregroundColor(Color(hex: "#1D3557"))

      VStack(alignment: .leading, spacing: 2) {

        Text("MISSING")
          .font(.system(size: 13, weight: .heavy))

        Text("Apple Intelligence.")
          .font(.system(size: 15, weight: .bold))

        Text("This is required for EVE to learn your routines from your daily context.")
          .font(.system(size: 13, weight: .semibold))
          .opacity(0.85)
          .fixedSize(horizontal: false, vertical: true)

      }
      .foregroundColor(Color(hex: "#1D3557"))

      Button {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          openURL(url)
        }
      } label: {
        Text("Allow")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color(hex: "#3B9CE2"), in: Capsule())
      }

    }
    .padding(20)
    .background(
      Color(hex: "#E7F0FA"),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .padding(.horizontal, 20)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  // MARK: - Continue

  private var continueButton: some View {
    Button {
      PermissionManager.shared.completeOnboarding()
      withAnimation {
        currentStep = 3 // Go to Home
      }
    } label: {
      Text("Continue to Home")
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(Color(hex: "#1D3557"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white, in: Capsule())
    }
    .padding(.horizontal, 32)
    .padding(.bottom, 24)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}

// MARK: - Components

private struct GlassIconTile: View {
  let systemName: String
  var rotation: Double = 0
  var size: CGFloat = 66

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
      .fill(Color.white.opacity(0.14))
      .frame(width: size, height: size)
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
          .stroke(Color.white.opacity(0.28), lineWidth: 1)
      )
      .overlay(
        Image(systemName: systemName)
          .font(.system(size: size * 0.4, weight: .medium))
          .foregroundColor(.white.opacity(0.9))
      )
      .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
      .rotationEffect(.degrees(rotation))
  }
}

private struct ThoughtBubble: View {
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Ellipse()
        .fill(Color.white)
        .frame(width: 62, height: 46)

      Circle()
        .fill(Color.white)
        .frame(width: 11, height: 11)
        .offset(x: -8, y: 5)

      Circle()
        .fill(Color.white)
        .frame(width: 5, height: 5)
        .offset(x: -16, y: 11)
    }
  }
}

private struct LearningLogRow: View {
  let icon: String
  let text: String
  var isActive: Bool = false
  var isLast: Bool = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {

      VStack(spacing: 0) {
        ZStack {
          Circle()
            .fill(Color.white)
            .frame(width: 28, height: 28)

          Image(systemName: icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Color(hex: "#1D3557"))
        }

        // Tail line: full segment between rows, short stub under
        // the active row (more is coming), nothing after the last.
        if !isLast {
          Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(width: 2, height: 26)
        } else if isActive {
          Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(width: 2, height: 16)
        }
      }

      Text(text)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(isActive ? Color.white.opacity(0.55) : .white)
        .padding(.top, 5)

      Spacer(minLength: 0)
    }
    .transition(
      .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .opacity
      )
    )
  }
}

#Preview {
    AILearningView(currentStep: .constant(2))
}
