import CoreLocation
import Foundation
import MapKit
import SwiftData

protocol RouteEstimating {
    func travelTime(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode) async throws -> TimeInterval
}

struct MapKitRouteEstimator: RouteEstimating {
    func travelTime(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        switch mode {
        case .driving: request.transportType = .automobile
        case .walking: request.transportType = .walking
        case .transit: request.transportType = .transit
        }
        return try await withCheckedThrowingContinuation { continuation in
            MKDirections(request: request).calculateETA { response, error in
                if let response { continuation.resume(returning: response.expectedTravelTime) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile)) }
            }
        }
    }
}

/// Turns Calendar + location context into stable local notification requests.
/// All persistence stays on the main actor with its ModelContext.
@MainActor
@Observable
final class AdaptiveNotificationCoordinator {
    private let context: ModelContext
    private let notifications: NotificationService
    private let routes: any RouteEstimating
    private let model = FoundationModelService()
    private let contextBuilder: ReminderContextBuilder

    private(set) var nextPlan: NotificationPlan?
    private(set) var isReconciling = false
    private(set) var lastError: String?

    init(
        context: ModelContext,
        notifications: NotificationService = .shared,
        routes: any RouteEstimating = MapKitRouteEstimator()
    ) {
        self.context = context
        self.notifications = notifications
        self.routes = routes
        contextBuilder = ReminderContextBuilder(context: context)
        notifications.onFeedback = { [weak self] occurrenceID, feedback in
            self?.record(feedback: feedback, for: occurrenceID)
        }
    }

    var travelMode: TravelMode {
        get { TravelMode(rawValue: UserDefaults.standard.string(forKey: "notif.travelMode") ?? "driving") ?? .driving }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "notif.travelMode") }
    }

    func reconcile(currentLocation: CLLocation? = nil) async {
        guard NotificationPreferences.isEnabled(forCategory: NotificationCategory.routine.rawValue) else {
            await notifications.cancelManagedRequests(except: [])
            return
        }
        let settings = await notifications.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        isReconciling = true
        lastError = nil
        defer { isReconciling = false }

        let now = Date.now
        let events = upcomingEvents(now: now)
        let existing = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<AdaptiveNotificationRecord>())) ?? []).map { ($0.occurrenceID, $0) })
        var plans: [NotificationPlan] = []

        for event in events.prefix(48) {
            if let plan = await makePlan(for: event, currentLocation: currentLocation, now: now) {
                plans.append(plan)
            }
        }
        plans.sort { $0.fireDate < $1.fireDate }

        // A late first sync should help with the next commitment once, not
        // deliver a burst of every alert whose ideal time is already gone.
        if let nearestLate = plans.first(where: { $0.fireDate <= now && $0.eventStart > now.addingTimeInterval(60) }),
           existing[nearestLate.occurrenceID] == nil {
            plans.removeAll { $0.occurrenceID == nearestLate.occurrenceID }
            plans.insert(NotificationPlan(
                occurrenceID: nearestLate.occurrenceID,
                identifier: nearestLate.identifier,
                fireDate: now.addingTimeInterval(5),
                eventStart: nearestLate.eventStart,
                title: nearestLate.title,
                body: nearestLate.body,
                reason: .catchUp,
                leaveBy: nearestLate.leaveBy,
                travelSeconds: nearestLate.travelSeconds,
                preparationMinutes: nearestLate.preparationMinutes
            ), at: 0)
        }

        let futurePlans = plans.filter { $0.fireDate > now }.prefix(48)
        var identifiers = Set<String>()
        for plan in futurePlans {
            identifiers.insert(plan.identifier)
            if let record = existing[plan.occurrenceID],
               record.fireDate == plan.fireDate,
               record.eventStart == plan.eventStart,
               record.isDelivered == false {
                continue
            }
            do {
                try await notifications.schedule(plan)
                upsert(plan: plan, existing: existing[plan.occurrenceID])
            } catch {
                lastError = error.localizedDescription
            }
        }
        await notifications.cancelManagedRequests(except: identifiers)
        nextPlan = futurePlans.first
        try? context.save()
    }

    func record(feedback: NotificationFeedback, for occurrenceID: String) {
        let descriptor = FetchDescriptor<AdaptiveNotificationRecord>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
        guard let record = try? context.fetch(descriptor).first else { return }
        record.feedbackRaw = feedback.rawValue
        record.isDelivered = true
        record.updatedAt = .now
        try? context.save()
        Task { await reconcile() }
    }

    /// Significant changes are intentionally sparse. We only persist a
    /// departure/arrival pair for the next relevant calendar trip, never a
    /// continuous location trail.
    func observeSignificantLocation(_ location: CLLocation) async {
        let now = Date.now
        guard let event = upcomingEvents(now: now).first(where: {
            $0.startDate.timeIntervalSince(now) <= 6 * 3600
        }), let destination = await destination(for: event) else {
            await reconcile(currentLocation: location)
            return
        }
        let samples = (try? context.fetch(FetchDescriptor<CommuteSample>())) ?? []
        if distance(location.coordinate, destination.coordinate) <= 250,
           let active = samples.first(where: { $0.occurrenceID == event.occurrenceID && $0.arrivedAt == nil }) {
            active.arrivedAt = now
            active.actualTravelSeconds = max(0, now.timeIntervalSince(active.departedAt))
            try? context.save()
        } else if samples.contains(where: { $0.occurrenceID == event.occurrenceID }) == false,
                  let origin = origin(for: event, destination: destination, currentLocation: nil, now: now),
                  distance(location.coordinate, origin.coordinate) > 250,
                  let record = record(for: event.occurrenceID),
                  now >= record.fireDate.addingTimeInterval(-90 * 60),
                  now < event.startDate {
            context.insert(CommuteSample(
                occurrenceID: event.occurrenceID,
                originKey: origin.key,
                destinationKey: destination.key,
                transportMode: travelMode,
                departedAt: now,
                expectedTravelSeconds: record.travelSeconds
            ))
            try? context.save()
        }
        await reconcile(currentLocation: location)
    }

    private func upcomingEvents(now: Date) -> [CalendarEvent] {
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate > now },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isAllDay }
    }

    private func makePlan(for event: CalendarEvent, currentLocation: CLLocation?, now: Date) async -> NotificationPlan? {
        let destination = await destination(for: event)
        let isOnline = destination == nil && event.meetingURL != nil
        let reason: TimingReason = destination == nil ? (isOnline ? .onlineEvent : .unresolvedLocation) : .physicalRoute
        let prep = await preparation(for: event, reason: reason)

        var travel: TimeInterval = 0
        var leaveBy: Date?
        if let destination, let origin = origin(for: event, destination: destination, currentLocation: currentLocation, now: now), distance(origin.coordinate, destination.coordinate) > 250 {
            if let eta = try? await routes.travelTime(from: origin.coordinate, to: destination.coordinate, mode: travelMode) {
                travel = adjustedTravel(eta, originKey: origin.key, destinationKey: destination.key)
                leaveBy = event.startDate.addingTimeInterval(-travel)
            }
        }

        let fireDate = event.startDate.addingTimeInterval(-(travel + TimeInterval(prep.minutes * 60)))
        let title = event.title.isEmpty ? "Upcoming event" : event.title
        let action = prep.action ?? defaultAction(for: event, reason: reason)
        let body: String
        if let leaveBy {
            body = "\(action) Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))."
        } else {
            body = "\(action) \(event.startDate.formatted(date: .omitted, time: .shortened))."
        }
        return NotificationPlan(
            occurrenceID: event.occurrenceID,
            identifier: identifier(for: event.occurrenceID),
            fireDate: fireDate,
            eventStart: event.startDate,
            title: title,
            body: body,
            reason: reason,
            leaveBy: leaveBy,
            travelSeconds: travel,
            preparationMinutes: prep.minutes
        )
    }

    private func preparation(for event: CalendarEvent, reason: TimingReason) async -> (minutes: Int, action: String?) {
        let fallback: Int
        switch reason {
        case .physicalRoute: fallback = 15
        case .onlineEvent: fallback = 10
        case .unresolvedLocation, .catchUp: fallback = 30
        }
        let prompt = contextBuilder.buildPreparationContext(
            eventTitle: event.title,
            eventDate: event.startDate,
            eventNotes: event.notes,
            eventLocation: event.location,
            eventAttendees: event.attendees,
            eventMeetingURL: event.meetingURL
        )
        // Model calls are intentionally limited to the next day. Long-range
        // alerts are deterministic until they become relevant and are then
        // replaced during a later reconciliation.
        var minutes = fallback
        var action: String?
        if event.startDate.timeIntervalSinceNow <= 24 * 3600, let prompt,
           let timing = try? await model.suggestTiming(forPromptText: prompt.promptText) {
            minutes = timing.preparationMinutes
            action = timing.action
        }
        minutes = min(120, max(5, minutes + feedbackAdjustment(for: reason)))
        return (minutes, action)
    }

    private func feedbackAdjustment(for reason: TimingReason) -> Int {
        let records = ((try? context.fetch(FetchDescriptor<AdaptiveNotificationRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? [])
            .filter { $0.reasonRaw == reason.rawValue }
            .prefix(10)
        let value = records.reduce(0) { partial, record in
            switch NotificationFeedback(rawValue: record.feedbackRaw ?? "") {
            case .tooEarly: return partial - 5
            case .tooLate: return partial + 10
            default: return partial
            }
        }
        return min(30, max(-30, value))
    }

    private func destination(for event: CalendarEvent) async -> (coordinate: CLLocationCoordinate2D, key: String)? {
        if let latitude = event.latitude, let longitude = event.longitude {
            return (CLLocationCoordinate2D(latitude: latitude, longitude: longitude), "event:\(event.occurrenceID)")
        }
        let places = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []
        if let place = places.first(where: { event.location?.localizedCaseInsensitiveContains($0.name) == true }),
           let latitude = place.latitude, let longitude = place.longitude {
            return (CLLocationCoordinate2D(latitude: latitude, longitude: longitude), "place:\(place.id.uuidString)")
        }
        guard let text = event.location, !text.isEmpty,
              let placemark = try? await CLGeocoder().geocodeAddressString(text).first,
              let coordinate = placemark.location?.coordinate else { return nil }
        return (coordinate, "text:\(text.lowercased())")
    }

    private func origin(for event: CalendarEvent, destination: (coordinate: CLLocationCoordinate2D, key: String), currentLocation: CLLocation?, now: Date) -> (coordinate: CLLocationCoordinate2D, key: String)? {
        if let currentLocation, now.timeIntervalSince(currentLocation.timestamp) <= 15 * 60,
           event.startDate.timeIntervalSince(now) <= 4 * 3600 {
            return (currentLocation.coordinate, "current")
        }
        let places = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []
        let home = places.first { $0.name.localizedCaseInsensitiveContains("home") }
        let office = places.first { $0.name.localizedCaseInsensitiveContains("office") || $0.name.localizedCaseInsensitiveContains("work") }
        let destinationIsOffice = office.map { place in
            guard let latitude = place.latitude, let longitude = place.longitude else { return false }
            return distance(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), destination.coordinate) <= 250
        } ?? false
        let useOffice = !destinationIsOffice && Calendar.current.component(.weekday, from: event.startDate) >= 2 && Calendar.current.component(.weekday, from: event.startDate) <= 6 && (9..<18).contains(Calendar.current.component(.hour, from: event.startDate))
        let preferred = useOffice ? office : home
        guard let place = preferred, let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return (CLLocationCoordinate2D(latitude: latitude, longitude: longitude), "place:\(place.id.uuidString)")
    }

    private func adjustedTravel(_ eta: TimeInterval, originKey: String, destinationKey: String) -> TimeInterval {
        let samples = ((try? context.fetch(FetchDescriptor<CommuteSample>())) ?? []).compactMap { sample -> Double? in
            guard sample.originKey == originKey, sample.destinationKey == destinationKey,
                  sample.transportModeRaw == travelMode.rawValue,
                  let actual = sample.actualTravelSeconds, sample.expectedTravelSeconds > 0 else { return nil }
            return actual / sample.expectedTravelSeconds
        }.sorted()
        guard samples.count >= 3 else { return eta }
        let percentile = samples[Int(Double(samples.count - 1) * 0.75)]
        return max(eta, eta * min(1.5, max(0.8, percentile)))
    }

    private func upsert(plan: NotificationPlan, existing: AdaptiveNotificationRecord?) {
        if let existing {
            existing.notificationIdentifier = plan.identifier
            existing.fireDate = plan.fireDate
            existing.eventStart = plan.eventStart
            existing.reasonRaw = plan.reason.rawValue
            existing.preparationMinutes = plan.preparationMinutes
            existing.travelSeconds = plan.travelSeconds
            existing.isDelivered = false
            existing.updatedAt = .now
        } else {
            context.insert(AdaptiveNotificationRecord(plan: plan))
        }
    }

    private func record(for occurrenceID: String) -> AdaptiveNotificationRecord? {
        let descriptor = FetchDescriptor<AdaptiveNotificationRecord>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
        return try? context.fetch(descriptor).first
    }

    private func identifier(for occurrenceID: String) -> String {
        let encoded = Data(occurrenceID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return NotificationService.calendarPrefix + encoded
    }

    private func distance(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    private func defaultAction(for event: CalendarEvent, reason: TimingReason) -> String {
        switch reason {
        case .onlineEvent: return "Get ready for \(event.title)."
        case .physicalRoute: return "Prepare for \(event.title)."
        case .unresolvedLocation, .catchUp: return "Prepare for \(event.title)."
        }
    }
}
