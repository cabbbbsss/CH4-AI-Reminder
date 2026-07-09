import SwiftUI

// MARK: - Apple Intelligence settings (Sketch artboard 6FC62177)

struct AppleIntelligenceSettingsView: View {
    @Bindable var permissionManager = PermissionManager.shared

    var body: some View {
        SettingsScaffold(title: "Apple Intelligence") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard {
                    SettingsToggleRow(label: "Learn from this App", isOn: $permissionManager.isAIEnabled)
                }

                Text("Allow Apple Intelligence to learn from how you use the synced apps to make suggestions and automate the reminders for you adaptively.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(.textQuarternary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
        }
    }
}

#Preview {
    NavigationStack {
        AppleIntelligenceSettingsView()
    }
}
