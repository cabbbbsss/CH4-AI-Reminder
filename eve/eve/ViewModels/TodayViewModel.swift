//
//  TodayViewModel.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

/// Composition root for the Today screen: owns the managers,
/// starts them in the right order, and exposes their state to the view.
/// The view renders; this decides.
@MainActor
@Observable
final class TodayViewModel {

    let sync: EventKitSyncManager

    let location: LocationActivityManager

    let assistant: AssistantManager

    let adaptiveNotifications: AdaptiveNotificationCoordinator

    private let notifications: NotificationService

    init(context: ModelContext) {

        let notifications = NotificationService.shared

        self.notifications = notifications
        self.sync = EventKitSyncManager(context: context)
        self.location = LocationActivityManager(context: context)
        self.assistant = AssistantManager(
            context: context,
            notificationService: notifications
        )
        self.adaptiveNotifications = AdaptiveNotificationCoordinator(
            context: context,
            notifications: notifications
        )

    }

    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var reconcileAgain = false

    // MARK: - Startup
    //
    // Three steps rather than one `start()`, so Home can build the day's
    // routine the moment the calendar is in. A single `start()` used to run
    // the import, a location fix and two full alert reconciles — each one a
    // geocode, a route and a model call per upcoming event — before the
    // routine was even begun, which on first launch meant minutes of an
    // empty list.

    /// Calendar access and the first import: all the routine needs.
    func startCalendar() async {
        await sync.start()
    }

    /// Location baseline and significant-change monitoring. Makes no model
    /// calls, so it can run alongside the routine.
    func startLocation() async {
        location.onSignificantLocationChange = { [weak self] location in
            Task { @MainActor [weak self] in
                await self?.adaptiveNotifications.observeSignificantLocation(location)
            }
        }
        await location.start()
    }

    /// Adaptive alerts: reconciles now and after every calendar sync. Called
    /// once the routine is built — reconciling asks the model about each of
    /// the next day's events, and started earlier those calls queue ahead of
    /// the routine's.
    func startNotifications() {
        sync.onSyncCompleted = { [weak self] in
            await self?.requestReconcile()
        }
        requestReconcile()
    }

    /// Reconciles pending alerts without holding up the caller — a sync used
    /// to wait for the whole pass. Requests that land mid-run fold into one
    /// more pass, so a burst of EventKit changes can't stack passes up.
    func requestReconcile() {
        guard reconcileTask == nil else {
            reconcileAgain = true
            return
        }
        reconcileTask = Task { [weak self] in
            while let self {
                self.reconcileAgain = false
                await self.adaptiveNotifications.reconcile(currentLocation: self.location.currentLocation)
                guard self.reconcileAgain else {
                    self.reconcileTask = nil
                    return
                }
            }
        }
    }

    /// Refreshes the Home suggestion bubble without scheduling a notification.
    /// The bubble is a dashboard preview; OS notifications are driven elsewhere.
    func askEve() async {
        await assistant.generateInitialInsights(currentPlace: location.currentPlace)
    }

}
