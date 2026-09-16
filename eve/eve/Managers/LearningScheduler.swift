import Foundation
import SwiftData

/// Evaluates upcoming calendar events and deduces proactive contextual learning items
/// (e.g. deduce "gloves" for a "Gym" event).
/// If deductions are found, it schedules a confirmation notification roughly 1 hour before.
final class LearningScheduler {
    
    private let context: ModelContext
    private let notifications = NotificationService.shared
    private let contextBuilder: ReminderContextBuilder
    
    init(context: ModelContext) {
        self.context = context
        self.contextBuilder = ReminderContextBuilder(context: context)
        bindNotificationFeedback()
    }
    
    /// Evaluates events that are approaching to deduce any learning items.
    func evaluateUpcomingEvents() async {
        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let now = Date.now
        
        // Find events starting in exactly 1-4 hours
        let upcoming = events.filter {
            let hoursUntil = $0.startDate.timeIntervalSince(now) / 3600
            return hoursUntil > 0.5 && hoursUntil < 4.0
        }
        
        // Find existing preferences to avoid spamming the user repeatedly for the same event type.
        let prefs = (try? context.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        let prefEventTypes = Set(prefs.map(\.eventType))
        
        for event in upcoming {
            // Check if we already have a preference (or an empty "checked" preference) for this event title
            if !prefEventTypes.contains(event.title) {
                await evaluateAndSchedule(for: event)
            }
        }
    }
    
    private func evaluateAndSchedule(for event: CalendarEvent) async {
        guard let prompt = contextBuilder.buildPreparationContext(
            eventTitle: event.title,
            eventDate: event.startDate,
            eventNotes: event.notes,
            eventLocation: event.location,
            eventAttendees: event.attendees,
            eventMeetingURL: event.meetingURL
        ) else { return }
        
        let service = FoundationModelService()
        do {
            let items = try await service.deduceContextualItems(forPromptText: prompt.promptText)
            
            guard !items.isEmpty else {
                // Save an empty, unconfirmed preference so we don't evaluate this event type again.
                let pref = ContextualPreference(eventType: event.title, items: [], confidence: 0, isUserConfirmed: false)
                context.insert(pref)
                try? context.save()
                return
            }
            
            // Save as unconfirmed with 0.5 confidence
            let pref = ContextualPreference(eventType: event.title, items: items, confidence: 0.5, isUserConfirmed: false)
            context.insert(pref)
            try? context.save()
            
            // Schedule notification ~1 hour before
            let notifyDate = event.startDate.addingTimeInterval(-3600)
            let fireDate = notifyDate > .now ? notifyDate : .now.addingTimeInterval(5)
            
            try? await notifications.scheduleLearningConfirmation(
                id: event.occurrenceID,
                eventType: event.title,
                items: items,
                at: fireDate
            )
            
        } catch {
            print("LearningScheduler failed to deduce items: \(error)")
        }
    }
    
    private func bindNotificationFeedback() {
        notifications.onLearningFeedback = { [weak self] action, eventType, items in
            guard let self else { return }
            Task {
                if action == "yes" {
                    await self.handleYes(eventType: eventType, items: items)
                } else if action == "no" {
                    await self.handleNo(eventType: eventType)
                } else if action == "customize" {
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenContextualCustomize"),
                            object: nil,
                            userInfo: ["eventType": eventType, "items": items]
                        )
                    }
                }
            }
        }
    }
    
    @MainActor
    private func handleYes(eventType: String, items: [String]) async {
        let prefs = (try? context.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        if let existing = prefs.first(where: { $0.eventType == eventType }) {
            existing.isUserConfirmed = true
            existing.confidence = 1.0
            existing.items = items
            try? context.save()
        }
    }
    
    @MainActor
    private func handleNo(eventType: String) async {
        let prefs = (try? context.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        if let existing = prefs.first(where: { $0.eventType == eventType }) {
            existing.confidence = 0.0
            existing.isUserConfirmed = true
            existing.items = []
            try? context.save()
        }
    }
}
