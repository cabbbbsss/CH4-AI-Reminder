import SwiftUI
import SwiftData

struct ContentView: View {
  @AppStorage("onboardingStep") private var currentStep: Int = 0
  @Bindable private var permissionManager = PermissionManager.shared
  @Environment(\.modelContext) private var modelContext

  @AppStorage("appThemePreference") private var themeRaw = AppThemePreference.system.rawValue

  private var preferredScheme: ColorScheme? {
    switch AppThemePreference(rawValue: themeRaw) ?? .system {
    case .system: return nil        // follow device
    case .light:  return .light
    case .dark:   return .dark
    }
  }

  var body: some View {
    Group {
      if permissionManager.hasCompletedOnboarding {
        HomeView()
      } else {
        switch currentStep {
        case 0:
          WelcomeView(currentStep: $currentStep)
        case 1:
          PermissionView(currentStep: $currentStep)
        case 2:
          AILearningView(currentStep: $currentStep)
        case 3:
          OnboardingQuestionsView(currentStep: $currentStep)
        default:
          HomeView()
        }
      }
    }
    .animation(.easeInOut, value: currentStep)
    .preferredColorScheme(preferredScheme)
    .task {
      // Clears beliefs stored before the shape check existed — advice and
      // passing observations that would otherwise re-enter every prompt.
      // A no-op once the store is clean.
      try? InsightManager(context: modelContext).pruneMalformed()
    }
  }
}

#Preview {
    ContentView()
}
