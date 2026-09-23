import Foundation
import SwiftData

@Model
final class ContextualPreference {
    
    /// The canonical activity name (e.g., "Gym", "Meeting", "Hike").
    /// Usually extracted from the calendar event title.
    var eventType: String
    
    /// The items the user typically needs for this event type (e.g., ["gloves", "whey", "AirPods"]).
    var items: [String]
    
    /// 0.0 to 1.0 — how confident the AI is about this association.
    var confidence: Double
    
    /// True if the user explicitly tapped "Yes" or customized the items via a notification or UI.
    var isUserConfirmed: Bool
    
    var lastUpdated: Date
    
    init(
        eventType: String,
        items: [String],
        confidence: Double = 0.5,
        isUserConfirmed: Bool = false,
        lastUpdated: Date = .now
    ) {
        self.eventType = eventType
        self.items = items
        self.confidence = confidence
        self.isUserConfirmed = isUserConfirmed
        self.lastUpdated = lastUpdated
    }
}
