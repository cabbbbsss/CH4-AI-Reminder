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

  /// True when the pass that ran did so without Apple Intelligence, so it can
  /// be re-run once if the user goes and turns it on.
  @State private var analyzedWithoutAI = false

  /// Indent for the streaming checklist. Wider than the standard gutter so
  /// the rows sit under the mascot rather than running edge to edge.
  private static let logInset: CGFloat = 56

  private var isFinished: Bool {
    !engine.isAnalyzing && engine.analysisProgress >= 1.0
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      AuroraBackground()

      VStack(spacing: 0) {
        mascotCluster
          .padding(.top, Theme.Spacing.m)

        Text(headline)
          .font(.eveScreenTitle.bold())
          .foregroundStyle(Color.eveOnSurface)
          .multilineTextAlignment(.center)
          .animation(.easeInOut, value: isFinished)
          .animation(.easeInOut, value: aiMissing)

        if aiMissing {

          missingAICard
            .padding(.top, Theme.Spacing.xl)

        } else {

          learningLog
            .padding(.top, Theme.Spacing.xl)
            .padding(.horizontal, Self.logInset)

        }

        Spacer(minLength: 0)
      }

      // Sits over the content rather than in the stack, so the log doesn't
      // shift down the moment the last step lands and the button appears.
      if isFinished {
        continueButton
          .padding(.trailing, Theme.Spacing.gutter)
          .padding(.bottom, Theme.Spacing.l)
      }
    }
    .overlay(alignment: .bottomLeading) {
      #if DEBUG
      // Always available, unlike Continue — the point is to be able to leave
      // this screen while the pass is still running.
      OnboardingBackButton(destination: 1, currentStep: $currentStep)
        .padding(.leading, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.l)
      #endif
    }
    // No forced `.preferredColorScheme(.dark)`. Welcome and Permission follow
    // the system, so pinning only these two screens to dark made onboarding
    // flip appearance halfway through for anyone in light mode — and it
    // overrode the theme preference ContentView applies.
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

  /// The "Enable" action on the paused card.
  ///
  /// Records the user's consent, then opens Settings so the user can turn on
  /// Apple Intelligence & Siri.
  ///
  /// NOTE: iOS gives third-party apps no public deep link to a *specific*
  /// Settings pane, so this lands on Eve's own Settings page and the user
  /// navigates up from there. The card's body text tells them where to go.
  /// (The private `App-Prefs:` scheme would open the Settings home directly,
  /// but it is grounds for rejection under App Review Guideline 2.5.1 — don't
  /// reintroduce it.) Re-collection happens on return (`.onChange(scenePhase)`).
  private func handleEnableTapped() {
    PermissionManager.shared.enableAI()

    if let appSettings = URL(string: UIApplication.openSettingsURLString) {
      openURL(appSettings)
    }
  }

  /// Runs the data-collection pass. Called on first appear AND every time the
  /// app returns to the foreground — so enabling Apple Intelligence in
  /// Settings and coming back re-triggers collection on its own.
  ///
  /// The pass runs whether or not Apple Intelligence is available. It already
  /// degrades by itself — insight extraction yields nothing and the question
  /// step falls back to `AILearningEngine.fallbackQuestions` — so refusing to
  /// start it only stranded the user. That mattered: this screen gates the
  /// entire app (the Continue button needs `isFinished`, which needs the pass
  /// to complete), and more than half of iPhones cannot run Apple Intelligence
  /// at all. The `aiMissing` card still explains what they're missing; it just
  /// no longer stops them reaching Eve.
  private func startIfPossible() async {

    let isAvailable = engine.isAppleIntelligenceAvailable

    aiMissing = !isAvailable

    // Allow exactly one re-run if Apple Intelligence was switched on after a
    // degraded pass — otherwise enabling it in Settings would leave the user
    // on the static fallback questions permanently.
    let shouldRetryWithAI = isAvailable && analyzedWithoutAI

    guard !engine.isAnalyzing, !hasStartedAnalysis || shouldRetryWithAI else { return }

    hasStartedAnalysis = true
    analyzedWithoutAI = !isAvailable

    await engine.analyzeUserRoutines(context: modelContext)

  }

  // MARK: - Mascot + floating data sources

  /// The mascot ringed by the data sources Eve is reading.
  ///
  /// The tiles used to sit at fixed ±145pt offsets, which pushed them off the
  /// edge of a 320pt-wide screen. The spread is now a fraction of the actual
  /// width, capped so it doesn't sprawl on an iPad.
  private var mascotCluster: some View {
    GeometryReader { proxy in
      let spread = min(proxy.size.width * 0.36, 145)

      ZStack {
        GlassIconTile(systemName: "calendar", rotation: -14)
          .offset(x: -spread * 0.86, y: -95)
          .offset(y: isFloating ? -6 : 6)
          .animation(floatAnimation(2.4), value: isFloating)

        GlassIconTile(systemName: "location.fill", rotation: 12)
          .offset(x: spread * 0.72, y: -115)
          .offset(y: isFloating ? 6 : -6)
          .animation(floatAnimation(2.8), value: isFloating)

        GlassIconTile(systemName: "clock", rotation: -10, size: 58)
          .offset(x: -spread, y: 15)
          .offset(y: isFloating ? -5 : 5)
          .animation(floatAnimation(3.0), value: isFloating)

        GlassIconTile(systemName: "checklist", rotation: 10, size: 58)
          .offset(x: spread * 0.97, y: 20)
          .offset(y: isFloating ? 5 : -5)
          .animation(floatAnimation(2.6), value: isFloating)

        Image("Avatar")
          .resizable()
          .scaledToFit()
          .frame(width: 190, height: 190)
          .scaleEffect(isFloating ? 1.03 : 0.97)
          .animation(floatAnimation(2.0), value: isFloating)

        // Eve is thinking. Empty cloud — the tiles around it already say
        // what she is thinking about.
        // Clear of the avatar (radius 95) and tucked into the gap between
        // the two tiles on that side, so nothing overlaps the face.
        ThoughtBubble(tail: .leading, tailDots: 2, width: 70)
          .offset(x: spread * 0.95, y: -75)
          .offset(y: isFloating ? -4 : 4)
          .animation(floatAnimation(2.2), value: isFloating)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .frame(height: 330)
    .accessibilityHidden(true)
    .onAppear {
      isFloating = true
    }
  }

  private func floatAnimation(_ duration: Double) -> Animation {
    .eveFloat(duration)
  }

  // MARK: - Streaming log

  private var learningLog: some View {
    VStack(alignment: .leading, spacing: 0) {

      ForEach(engine.completedSteps) { step in
        LearningLogRow(
          // ✓ when the step had data to work with, ✗ when nothing was
          // available (the relevant permission wasn't granted).
          icon: step.succeeded ? "checkmark" : "xmark",
          iconColor: step.succeeded ? .accentColor : .red,
          text: step.text,
          detail: step.detail,
          isActive: false,
          isLast: !engine.isAnalyzing && step.id == engine.completedSteps.last?.id
        )
      }

      if engine.isAnalyzing {
        LearningLogRow(
          icon: "ellipsis",
          iconColor: .eveOnSurfaceMuted,
          // Only shown for the instant before the first step names itself.
          text: engine.currentAnalysisTask.isEmpty
            ? "Getting started…"
            : engine.currentAnalysisTask,
          detail: engine.currentAnalysisDetail,
          isActive: true,
          isLast: true
        )
      }

    }
    .animation(
      .spring(response: 0.5, dampingFraction: 0.8),
      value: engine.completedSteps.count
    )
  }

  // MARK: - Missing Apple Intelligence

  /// A light card, matching every other surface on this screen.
  ///
  /// It used to be drawn on the inverted panel colour, which put an
  /// Apple Intelligence glyph in exactly the same colour as its own
  /// background — the icon was invisible. On `eveSurface` the whole card
  /// uses the ordinary on-surface colours and can't collide with itself.
  private var missingAICard: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.m) {

      Image(systemName: "apple.intelligence")
        .font(.system(size: 34))
        .foregroundStyle(Color.accentColor)

      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        Text("MISSING")
          .font(.eveCardTitle)
          .foregroundStyle(Color.eveOnSurface)

        Text("Apple Intelligence.")
          .font(.eveCardTitle)
          .foregroundStyle(Color.eveOnSurface)

        Text("This is required for EVE to learn your routines from your daily context.")
          .font(.eveDetail)
          .foregroundStyle(Color.eveOnSurface.opacity(0.75))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, Theme.Spacing.xxs)
      }

      Spacer(minLength: Theme.Spacing.xs)

      Button {
        handleEnableTapped()
      } label: {
        Text("Allow")
          .font(.eveCaption)
          .foregroundStyle(.white)
          .padding(.horizontal, Theme.Spacing.m)
          .padding(.vertical, Theme.Spacing.xs)
          .background(Color.accentColor, in: Capsule())
      }
      // Nudged down to sit against the name rather than the MISSING label.
      .padding(.top, Theme.Spacing.m)
    }
    .padding(Theme.Spacing.m)
    .eveCard(radius: Theme.Radius.panel)
    .padding(.horizontal, Theme.Spacing.gutter)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  // MARK: - Continue

  /// The same circular glass control the permission step uses, so the two
  /// onboarding screens advance the same way.
  private var continueButton: some View {
    Button {
      // Onboarding isn't finished yet — go to the questions step.
      withAnimation {
        currentStep = 3
      }
    } label: {
      Image(systemName: "chevron.right")
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.eveOnSurface)
        .frame(width: 26, height: 26)
        .padding(Theme.Spacing.s)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .accessibilityLabel("Continue")
    .transition(.opacity.combined(with: .scale))
  }
}

// MARK: - Components

private struct GlassIconTile: View {
  let systemName: String
  var rotation: Double = 0
  var size: CGFloat = 66

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
      .fill(Color.eveSurface.opacity(0.75))
      .frame(width: size, height: size)
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
          .stroke(Color.eveOnSurface.opacity(0.10), lineWidth: 1)
      )
      .overlay(
        Image(systemName: systemName)
          .font(.system(size: size * 0.4, weight: .medium))
          .foregroundStyle(Color.eveOnSurface.opacity(0.35))
      )
      .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
      .rotationEffect(.degrees(rotation))
  }
}

private struct LearningLogRow: View {
  let icon: String
  var iconColor: Color = .accentColor
  let text: String
  var detail: String = ""
  var isActive: Bool = false
  var isLast: Bool = false

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.s) {

      VStack(spacing: 0) {
        ZStack {
          Circle()
            .fill(Color.eveSurface)
            .frame(width: 28, height: 28)

          Image(systemName: icon)
            .font(.eveCaption.weight(.bold))
            .foregroundStyle(iconColor)
        }

        // Tail line: stretches to whatever height this row turned out to be,
        // short stub under the active row (more is coming), nothing after the
        // last. It used to be a fixed 30pt, so any row whose detail wrapped to
        // two lines outgrew its own connector and collided with the next one.
        if !isLast {
          Rectangle()
            .fill(Color.eveSurface.opacity(0.7))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
        } else if isActive {
          Rectangle()
            .fill(Color.eveSurface.opacity(0.7))
            .frame(width: 2, height: 16)
        }
      }
      .frame(maxHeight: .infinity)

      VStack(alignment: .leading, spacing: 2) {
        // The active row stays dimmer, so the step in flight reads as
        // in-progress rather than done.
        Text(text)
          .font(.eveBody)
          .foregroundStyle(Color.eveOnSurface.opacity(isActive ? 0.55 : 1))

        if !detail.isEmpty {
          Text(detail)
            .font(.eveDetail)
            .foregroundStyle(Color.eveOnSurfaceMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, 3)
      // The gap between rows lives here rather than on the stack, so the
      // connector above stretches through it instead of stopping short.
      .padding(.bottom, isLast ? 0 : Theme.Spacing.m)

      Spacer(minLength: 0)
    }
    .fixedSize(horizontal: false, vertical: true)
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
