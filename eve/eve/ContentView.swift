import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
  @AppStorage("onboardingStep") private var currentStep: Int = 0
  @Bindable private var permissionManager = PermissionManager.shared
  @Bindable private var permissionRecovery = PermissionRecoveryCoordinator.shared
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

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
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        permissionManager.refreshStatuses()
      }
    }
    .alert(item: $permissionRecovery.activeRecovery) { recovery in
      Alert(
        title: Text(recovery.title),
        message: Text(recovery.message),
        primaryButton: .default(Text("Open Settings")) {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        },
        secondaryButton: .cancel(Text("Not Now"))
      )
    }
  }
}

#Preview {
    ContentView()
}
