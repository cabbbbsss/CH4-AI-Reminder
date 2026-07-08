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
@Observable
final class TodayViewModel {

    let sync: EventKitSyncManager

    let location: LocationActivityManager

    let assistant: AssistantManager

    private let notifications: NotificationService

    init(context: ModelContext) {

        let notifications = NotificationService()

        self.notifications = notifications
        self.sync = EventKitSyncManager(context: context)
        self.location = LocationActivityManager(context: context)
        self.assistant = AssistantManager(
            context: context,
            notificationService: notifications
        )

    }

    /// Sequential on purpose: one permission dialog at a time.
    func start() async {
        await sync.start()
        await location.start()
    }

    func askEve() async {
        await notifications.requestPermission()
        await assistant.runOnce(currentPlace: location.currentPlace)
    }

}
