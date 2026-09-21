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
        case backgroundLocation

        var id: String {
            switch self {
            case .notifications: "notifications"
            case .backgroundLocation: "backgroundLocation"
            }
        }

        var title: String {
            switch self {
            case .notifications: "Notifications are off"
            case .backgroundLocation: "Location is set to While Using"
            }
        }

        var message: String {
            switch self {
            case .notifications:
                "Your reminder was saved, but EVE cannot notify you until notifications are enabled in Settings."
            case .backgroundLocation:
                "Your place reminder was saved, but EVE can only alert you on arrival while it is open. Set Location to Always in Settings to be reminded when EVE is closed."
            }
        }
    }

    var activeRecovery: Recovery?

    func presentNotificationsRecovery() {
        activeRecovery = .notifications
    }

    /// iOS asks for Always at most once; after that Settings is the only route.
    func presentBackgroundLocationRecovery() {
        activeRecovery = .backgroundLocation
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
