import SwiftUI

// MARK: - Notification settings (Sketch artboard 093EAC1C)

struct NotificationSettingsView: View {
    @State private var routineReminders = true
    @State private var insightAlerts = true
    @State private var actionableNotifications = true

    var body: some View {
        SettingsScaffold(title: "Notification") {
            VStack(spacing: 24) {
                SettingsCard {
                    SettingsToggleRow(label: "Routine Reminders", isOn: $routineReminders)
                    SettingsDivider()
                    SettingsToggleRow(label: "Insight Alerts", isOn: $insightAlerts)
                    SettingsDivider()
                    SettingsToggleRow(label: "Actionable Notifications", isOn: $actionableNotifications)
                }
            }
            .padding(.top, 20)
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
