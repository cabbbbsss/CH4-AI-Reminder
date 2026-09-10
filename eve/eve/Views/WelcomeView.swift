import SwiftUI

/// The splash screen: Eve's mascot running off the trailing edge, a thought
/// bubble, and the wordmark — held long enough to read, then handed off to
/// the permission step.
///
/// The hand-off is a move, not a cut. Eve walks from the trailing edge to the
/// leading edge — landing exactly where `PermissionView` draws her — and only
/// then does the step advance. Both screens read the same `MascotPlacement`
/// values, so the cross-fade between them has nothing left to move and reads
/// as one continuous shot.
struct WelcomeView: View {
    @Binding var currentStep: Int

    /// Drives the entrance so the screen doesn't just appear fully formed —
    /// it settles in over the beat before it hands off.
    @State private var hasAppeared = false

    /// Eve is on her way to the permission screen: the wordmark and bubble
    /// clear out and she crosses to the leading edge.
    @State private var isDeparting = false

    /// How long the splash holds before Eve sets off.
    private static let hold: Duration = .seconds(2.5)

    /// How long she takes to cross the screen.
    private static let departure: Double = 0.95

    var body: some View {
        // Every element is placed as a fraction of the real screen size, so
        // the composition holds together from an iPhone SE to an iPad rather
        // than being pinned to one device's point dimensions.
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                // Sits low behind the wordmark, then rises to the permission
                // screen's height as Eve crosses — so the two backgrounds are
                // identical by the time they cross-fade.
                AuroraBackground(
                    focus: isDeparting ? AuroraBackground.defaultFocus : 0.45
                )

                avatar(in: size)
                bubble(in: size)
                wordmark(in: size)
            }
            .frame(width: size.width, height: size.height)
        }
        // The mascot is deliberately cut off by the display edge, so the
        // layout has to measure the full screen, not the safe area.
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eve — your adaptive routine companion")
        // `.task` is cancelled when the view goes away, so the hand-off can't
        // fire into a screen that's already been replaced.
        .task {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) {
                hasAppeared = true
            }

            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: Self.departure)) {
                isDeparting = true
            }

            // Advance only once she has arrived. Handing off mid-walk would
            // cross-fade a moving mascot into a stationary one, which is
            // exactly the jump this sequence is built to avoid.
            try? await Task.sleep(for: .seconds(Self.departure))
            guard !Task.isCancelled else { return }

            withAnimation { currentStep = 1 }
        }
    }

    // MARK: - Mascot

    /// Starts centred just past the trailing edge — only her leading half on
    /// screen — and crosses to the permission screen's placement on departure.
    private func avatar(in size: CGSize) -> some View {
        let widthRatio = isDeparting
            ? MascotPlacement.permissionWidth
            : MascotPlacement.splashWidth

        let centerXRatio = isDeparting
            ? MascotPlacement.permissionCenterX
            : MascotPlacement.splashCenterX

        return Image("Avatar")
            .resizable()
            .scaledToFit()
            .frame(width: size.width * widthRatio)
            .floating(7, period: MascotPlacement.floatPeriod)
            .scaleEffect(hasAppeared ? 1 : 0.92)
            .position(
                x: size.width * centerXRatio,
                y: size.height * MascotPlacement.centerY
            )
    }

    // MARK: - Thought bubble

    private func bubble(in size: CGSize) -> some View {
        // Tail points right, towards the mascot bleeding off that edge.
        ThoughtBubble(systemName: "list.bullet", tail: .trailing, width: size.width * 0.315)
            .floating(5, period: MascotPlacement.bubbleFloatPeriod)
            .opacity(hasAppeared && !isDeparting ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .position(x: size.width * 0.318, y: size.height * 0.395)
    }

    // MARK: - Wordmark

    private func wordmark(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // Pushes the block to roughly the lower third without pinning it
            // to the bottom — the mockup leaves deliberate space underneath.
            Spacer(minLength: 0)
                .frame(height: size.height * 0.545)

            Text("EVE")
                // Thin and widely tracked. Capped so the wordmark doesn't
                // balloon on a large display.
                .font(.system(size: min(size.width * 0.175, 96), weight: .thin))
                .tracking(size.width * 0.055)
                .foregroundStyle(Color.eveOnSurface)

            // The break is explicit: the tagline is set as two balanced lines
            // under the wordmark, and leaving it to wrap on its own put
            // "routine" on the second line, which reads worse. maxWidth still
            // lets it re-wrap rather than run under the mascot at large
            // Dynamic Type sizes.
            Text("Your adaptive routine\ncompanion")
                .font(.eveDetail)
                .foregroundStyle(Color.eveOnSurface.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: size.width * 0.6, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, Theme.Spacing.gutter)
        // Clears out as Eve crosses, so she isn't walking over the wordmark.
        .opacity(hasAppeared && !isDeparting ? 1 : 0)
    }
}

#Preview {
  WelcomeView(currentStep: .constant(0))
}
