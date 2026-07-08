import SwiftUI
import SwiftData

struct ContentView: View {
  @AppStorage("onboardingStep") private var currentStep: Int = 0
  @Bindable private var permissionManager = PermissionManager.shared
  
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
        default:
          HomeView()
        }
      }
    }
    .animation(.easeInOut, value: currentStep)
  }
}

#Preview {
    ContentView()
}
