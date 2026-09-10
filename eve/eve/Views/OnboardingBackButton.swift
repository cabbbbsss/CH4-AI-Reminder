#if DEBUG
import SwiftUI

/// Steps *backwards* through onboarding, for testing only.
///
/// Onboarding is a one-way flow in the product — each step consumes something
/// (a permission answer, a learning pass, a set of questions) and there is
/// nothing to return to once it's done. This exists purely so an earlier
/// screen can be looked at again without reinstalling the app or hand-editing
/// `onboardingStep` in UserDefaults.
///
/// It is compiled out of release builds. To ship it, delete the `#if DEBUG`
/// here and the ones around each call site.
struct OnboardingBackButton: View {

    /// The step to return to.
    var destination: Int

    @Binding var currentStep: Int

    var body: some View {
        Button {
            withAnimation { currentStep = destination }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.eveOnSurface)
                .frame(width: 26, height: 26)
                .padding(Theme.Spacing.s)
        }
        // Mirrors the forward control on the same screens, so the pair reads
        // as one set rather than a debug affordance bolted on.
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Back (testing only)")
    }
}
#endif
