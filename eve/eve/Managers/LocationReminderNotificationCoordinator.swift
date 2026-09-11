import CoreLocation
import SwiftData
import UserNotifications

/// Installs native entry notifications for user-owned reminders at confirmed
/// places. The OS owns region monitoring; EVE does not retain a location trail.
@MainActor
final class LocationReminderNotificationCoordinator {
    static let shared = LocationReminderNotificationCoordinator()

    private let notifications = NotificationService.shared

    func scheduleAfterManualSave(_ reminder: LocationReminder, at location: SavedLocation) async {
        let locationStatus = await PermissionManager.shared.requestLocationIfUndetermined()
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else { return }

        let notificationStatus = await PermissionManager.shared.notificationAuthorizationStatus()
        if notificationStatus == .notDetermined {
            _ = await PermissionManager.shared.requestNotificationsIfUndetermined()
        } else if notificationStatus == .denied {
            PermissionRecoveryCoordinator.shared.presentNotificationsRecovery()
            return
        }

        guard PermissionManager.canDeliverNotifications(
            await PermissionManager.shared.notificationAuthorizationStatus()
        ) else { return }
        await schedule(reminder, at: location)
    }

    func reconcile(context: ModelContext) async {
        guard PermissionManager.shared.locationAuthorizationStatus() == .authorizedWhenInUse
                || PermissionManager.shared.locationAuthorizationStatus() == .authorizedAlways,
              PermissionManager.canDeliverNotifications(
                await PermissionManager.shared.notificationAuthorizationStatus()
              )
        else { return }

        let locations = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        let reminders = ((try? context.fetch(FetchDescriptor<LocationReminder>())) ?? [])
            .filter { !$0.isSystemManaged && !$0.isCompleted }
            .prefix(20)

        let schedulable = reminders.compactMap { reminder -> (LocationReminder, SavedLocation)? in
            guard let location = byID[reminder.locationID],
                  location.latitude != nil,
                  location.longitude != nil else { return nil }
            return (reminder, location)
        }
        let identifiers = Set(schedulable.map { identifier(for: $0.0) })
        await notifications.cancelLocationRequests(except: identifiers)
        for (reminder, location) in schedulable {
            await schedule(reminder, at: location)
        }
    }

    func cancel(_ reminder: LocationReminder) {
        notifications.cancelLocationReminder(id: identifier(for: reminder))
    }

    private func schedule(_ reminder: LocationReminder, at location: SavedLocation) async {
        guard let latitude = location.latitude, let longitude = location.longitude else { return }
        try? await notifications.scheduleLocationReminder(
            id: identifier(for: reminder),
            title: "When you arrive at \(location.name)",
            body: reminder.text,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    private func identifier(for reminder: LocationReminder) -> String {
        NotificationService.locationPrefix + reminder.id.uuidString
    }
}
