import SwiftUI
import UIKit

// MARK: - OS permission status (Calendar / Reminder)

/// Read-only status screen for an OS-level permission. iOS doesn't let apps
/// grant or revoke these directly, so this surfaces the current authorization
/// state and deep-links to the app's page in the Settings app to change it.
struct PermissionStatusSettingsView: View {
    let title: String
    let statusKeyPath: KeyPath<PermissionManager, Bool>
    let description: String
    @Bindable private var permissionManager = PermissionManager.shared

    private var isGranted: Bool { permissionManager[keyPath: statusKeyPath] }

    var body: some View {
        SettingsScaffold(title: title) {
            VStack(alignment: .leading, spacing: 16) {
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

                Text(description)
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
            }
            .padding(.top, 20)
        }
        // Refresh so a permission changed in the Settings app is reflected on return.
        .onAppear { permissionManager.refreshStatuses() }
    }
}

#Preview {
    NavigationStack {
        PermissionStatusSettingsView(
            title: "Calendar",
            statusKeyPath: \.isCalendarGranted,
            description: "EVE reads and updates your calendar events to build your routine and schedule reminders. Calendar access is managed by iOS — use the Settings app to change it."
        )
    }
}
