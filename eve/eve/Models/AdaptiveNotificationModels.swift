import Foundation
import SwiftData

enum TravelMode: String, CaseIterable, Codable {
    case driving, walking, transit

    var displayName: String { rawValue.capitalized }
}

enum TimingReason: String, Codable {
    case physicalRoute
    case onlineEvent
    case unresolvedLocation
    case catchUp
}

enum NotificationFeedback: String, Codable {
    case done
    case tooEarly
    case tooLate
}

/// The bounded output requested from the on-device model. The coordinator
/// validates the minutes before it affects a real notification.
struct EventTimingSuggestion: Sendable {
    let preparationMinutes: Int
    let action: String?
}

struct NotificationPlan: Sendable {
    let occurrenceID: String
    let identifier: String
    let fireDate: Date
    let eventStart: Date
    let title: String
    let body: String
    let reason: TimingReason
    let leaveBy: Date?
    let travelSeconds: TimeInterval
    let preparationMinutes: Int
}

/// Persistent bookkeeping prevents a delivered or re-planned alert from
/// being re-added every time EventKit posts a change notification.
@Model
final class AdaptiveNotificationRecord {
    @Attribute(.unique) var occurrenceID: String
    var notificationIdentifier: String
    var fireDate: Date
    var eventStart: Date
    var reasonRaw: String
    var preparationMinutes: Int
    var travelSeconds: Double
    var feedbackRaw: String?
    var isDelivered: Bool = false
    var updatedAt: Date = Date.now

    init(plan: NotificationPlan) {
        occurrenceID = plan.occurrenceID
        notificationIdentifier = plan.identifier
        fireDate = plan.fireDate
        eventStart = plan.eventStart
        reasonRaw = plan.reason.rawValue
        preparationMinutes = plan.preparationMinutes
        travelSeconds = plan.travelSeconds
    }
}

/// A completed trip only; EVE deliberately does not retain a raw location
/// trace. Samples make future route estimates personal without a server.
@Model
final class CommuteSample {
    var occurrenceID: String
    var originKey: String
    var destinationKey: String
    var transportModeRaw: String
    var departedAt: Date
    var arrivedAt: Date?
    var expectedTravelSeconds: Double
    var actualTravelSeconds: Double?

    init(
        occurrenceID: String,
        originKey: String,
        destinationKey: String,
        transportMode: TravelMode,
        departedAt: Date,
        arrivedAt: Date? = nil,
        expectedTravelSeconds: Double
    ) {
        self.occurrenceID = occurrenceID
        self.originKey = originKey
        self.destinationKey = destinationKey
        transportModeRaw = transportMode.rawValue
        self.departedAt = departedAt
        self.arrivedAt = arrivedAt
        self.expectedTravelSeconds = expectedTravelSeconds
    }
}
