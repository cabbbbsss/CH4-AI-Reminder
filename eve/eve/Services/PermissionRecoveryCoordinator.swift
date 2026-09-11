import Foundation
import Observation
import UserNotifications

/// A single recovery surface for permission decisions iOS will not ask again.
@MainActor
@Observable
final class PermissionRecoveryCoordinator {
    static let shared = PermissionRecoveryCoordinator()

    enum Recovery: Identifiable {
        case notifications

        var id: String { "notifications" }

        var title: String { "Notifications are off" }

        var message: String {
            "Your reminder was saved, but EVE cannot notify you until notifications are enabled in Settings."
        }
    }

    var activeRecovery: Recovery?

    func presentNotificationsRecovery() {
        activeRecovery = .notifications
    }

    /// A saved manual reminder is never conditional on permission. This only
    /// asks on the first decision, then offers Settings after a prior denial.
    func checkNotificationsAfterManualReminder() async {
        let status = await PermissionManager.shared.notificationAuthorizationStatus()
        if status == .notDetermined {
            _ = await PermissionManager.shared.requestNotificationsIfUndetermined()
        } else if status == .denied {
            presentNotificationsRecovery()
        }
    }
}
