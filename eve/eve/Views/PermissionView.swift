import SwiftUI

/// Onboarding step two: explains what Eve reads, then asks for Calendar.
///
/// Eve only needs the calendar to build a routine, so this is the single
/// permission onboarding requests. Location is asked for later, at the moment
/// the user actually creates a place-based reminder (see `AddLocationSheet`),
/// and notifications the first time Eve has something to deliver — permissions
/// land where the user can see what they buy.
struct PermissionView: View {
    @Binding var currentStep: Int
    @Bindable var permissionManager = PermissionManager.shared

    /// Guards against double-taps while the OS prompt is being presented.
    @State private var isRequesting = false

    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // The artwork measures the whole display so the mascot can bleed
            // off the leading edge; the button below stays inside the safe
            // area, which is why they are siblings rather than nested.
            GeometryReader { proxy in
                let size = proxy.size

                ZStack(alignment: .topLeading) {
                    AuroraBackground()

                    avatar(in: size)
                    bubble(in: size)
                    copy(in: size)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()

            nextButton
                .padding(.trailing, Theme.Spacing.gutter)
                .padding(.bottom, Theme.Spacing.l)
        }
        .overlay(alignment: .bottomLeading) {
            #if DEBUG
            // Returns to the splash, which then replays its walk back to here.
            OnboardingBackButton(destination: 0, currentStep: $currentStep)
                .padding(.leading, Theme.Spacing.gutter)
                .padding(.bottom, Theme.Spacing.l)
            #endif
        }
        .task {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Mascot

    /// Mirrors the splash: centred on the leading edge so only Eve's trailing
    /// half is on screen, leaving the right side of the display for the copy.
    ///
    /// Deliberately has no entrance animation of its own. The splash walks its
    /// mascot to exactly this placement before advancing, so by the time this
    /// screen mounts Eve is already standing here — scaling her in again would
    /// put a visible pop in the middle of an otherwise continuous move. The
    /// bubble and copy below still animate, since they have nothing to match.
    private func avatar(in size: CGSize) -> some View {
        Image("Avatar")
            .resizable()
            .scaledToFit()
            .frame(width: size.width * MascotPlacement.permissionWidth)
            .floating(7, period: MascotPlacement.floatPeriod)
            .position(
                x: size.width * MascotPlacement.permissionCenterX,
                y: size.height * MascotPlacement.centerY
            )
    }

    // MARK: - Thought bubble

    private func bubble(in size: CGSize) -> some View {
        // Tail points left, back towards the mascot on that edge.
        ThoughtBubble(
            systemName: "apple.intelligence",
            tail: .leading,
            tailDots: 2,
            width: size.width * 0.31
        )
        .floating(5, period: MascotPlacement.bubbleFloatPeriod)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .position(x: size.width * 0.65, y: size.height * 0.386)
    }

    // MARK: - Copy

    private func copy(in size: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            Spacer(minLength: 0)
                .frame(height: size.height * 0.50)

            Text("Enhance\nYour Assistant")
                .font(.eveScreenTitle.bold())
                .foregroundStyle(Color.eveOnSurface)
                .multilineTextAlignment(.trailing)

            Text("EVE works by understanding your world to remind you. All data stored on your device, never anywhere else.")
                .font(.eveBody)
                .foregroundStyle(Color.eveOnSurface.opacity(0.7))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                // Held to the right half so the lines stack under the heading
                // instead of running back under the mascot.
                .frame(maxWidth: size.width * 0.56, alignment: .trailing)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Theme.Spacing.gutter)
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Continue

    private var nextButton: some View {
        Button {
            requestCalendarThenContinue()
        } label: {
            Group {
                if isRequesting {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(Color.eveOnSurface)
            .frame(width: 26, height: 26)
            .padding(Theme.Spacing.s)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(isRequesting)
        .accessibilityLabel("Continue")
    }

    /// Presents the system Calendar prompt, then moves on regardless of the
    /// answer — the permission is the user's choice, and Eve degrades to an
    /// empty routine rather than trapping them on this screen.
    private func requestCalendarThenContinue() {
        guard !isRequesting else { return }
        isRequesting = true

        Task {
            await permissionManager.requestOnboardingPermissions()
            isRequesting = false
            withAnimation {
                currentStep = 2
            }
        }
    }
}

#Preview {
    PermissionView(currentStep: .constant(1))
}
