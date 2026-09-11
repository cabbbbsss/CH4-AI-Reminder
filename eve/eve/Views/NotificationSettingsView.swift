import SwiftUI
import UIKit

// MARK: - Notification settings (Sketch artboard 093EAC1C)

/// Notifications are an OS-level permission: iOS decides whether Eve may post
/// them at all, and an app can't grant or revoke that itself. So the top of the
/// screen mirrors the other permission screens (Calendar / Reminder / Location):
/// it reflects the real authorization read by `PermissionManager` and deep-links
/// to the Settings app to change it.
///
/// The per-category switches below are Eve's *own* preference for which kinds of
/// notification to send once the OS permission is granted. They're persisted
/// with `@AppStorage` (so they survive relaunches instead of resetting) and are
/// disabled while notifications are off, since they're meaningless without the
/// OS permission.
struct NotificationSettingsView: View {
    @Bindable private var permissionManager = PermissionManager.shared

    @AppStorage("notif.routineReminders") private var routineReminders = true
    @AppStorage("notif.insightAlerts") private var insightAlerts = true
    @AppStorage("notif.actionableNotifications") private var actionableNotifications = true
    @AppStorage("notif.travelMode") private var travelModeRaw = TravelMode.driving.rawValue
    @State private var showBackgroundLocationExplanation = false

    private var isGranted: Bool { permissionManager.isNotificationsGranted }

    var body: some View {
        SettingsScaffold(title: "Notification") {
            VStack(alignment: .leading, spacing: 16) {
                // Real OS permission status — matches Calendar / Reminder / Location.
                SettingsCard {
                    HStack {
                        Text("Access")
                            .font(.system(size: 17))
                            .foregroundColor(Color(.textPrimary))
                        Spacer()
                        Text(isGranted ? "Granted" : "Not Granted")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isGranted ? .green : Color(.textQuarternary))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                }

                Text("EVE sends reminders and alerts through notifications. Whether EVE may deliver them is managed by iOS — use the Settings app to change it.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(.textQuarternary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open in Settings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(.textSecondary))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentColor)
                        .cornerRadius(20)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)

                // App-level preference: which notification types EVE may send.
                // Inert while the OS permission is off — nothing can be delivered.
                SettingsCard {
                    SettingsToggleRow(label: "Routine Reminders", isOn: $routineReminders)
                    SettingsDivider()
                    SettingsToggleRow(label: "Insight Alerts", isOn: $insightAlerts)
                    SettingsDivider()
                    SettingsToggleRow(label: "Actionable Notifications", isOn: $actionableNotifications)
                }
                .disabled(!isGranted)
                .opacity(isGranted ? 1 : 0.4)

                SettingsCard {
                    Picker("Travel mode", selection: $travelModeRaw) {
                        ForEach(TravelMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .padding(.horizontal, 18)

                    SettingsDivider()

                    Button("Enable adaptive background timing") {
                        showBackgroundLocationExplanation = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                }

                Text("EVE uses your selected travel mode, confirmed Home/Office pins, and low-power location changes to refine future alerts. Location history stays on this device.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(.textQuarternary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
        }
        // Reflect a permission changed in the Settings app when we return.
        .onAppear { permissionManager.refreshStatuses() }
        .alert("Enable adaptive background timing?", isPresented: $showBackgroundLocationExplanation) {
            Button("Not Now", role: .cancel) {}
            Button("Continue") {
                Task { await permissionManager.requestAdaptiveBackgroundLocation() }
            }
        } message: {
            Text("EVE first asks for location while you use the app, then may ask separately for Always access so it can refine travel timing in the background.")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
