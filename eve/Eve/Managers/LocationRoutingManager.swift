//
//  LocationRoutingManager.swift
//  Eve
//
//  Created by cabsss on 08/07/26.
//

import Foundation
import SwiftData

/// Routes real calendar events and reminders onto the user's saved
/// locations (Home, Office, and anything else they've added).
///
/// Two-stage routing, same principle used everywhere else in the AI
/// pipeline: resolve what can be resolved deterministically first, only
/// hand the model what's genuinely ambiguous.
/// 1. Deterministic — item title shares a keyword with a place's name or
///    address. No AI call needed, can't hallucinate.
/// 2. AI classification — whatever's left, batched into one call, with
///    the user's own prior corrections given as ground-truth examples.
final class LocationRoutingManager {

    private let context: ModelContext

    private let foundationModel: FoundationModelService

    private let contextBuilder: ReminderContextBuilder

    private static let stopwords: Set<String> = [
        "a", "an", "the", "at", "in", "on", "for", "to", "of", "and", "with",
        "is", "are", "this", "that", "your", "you", "me", "my", "it", "be",
        "do", "not", "no", "yes", "today", "tomorrow", "day", "time"
    ]

    init(context: ModelContext, foundationModel: FoundationModelService = FoundationModelService()) {
        self.context = context
        self.foundationModel = foundationModel
        self.contextBuilder = ReminderContextBuilder(context: context)
    }

    /// Seeds LocationReminder rows for every saved place from real
    /// calendar/reminder data. Only touches items that haven't been routed
    /// before (tracked via LocationAssignment), so it's safe to call again
    /// as a "refresh" — it just picks up anything new.
    func seedReminders() async {

        let locations = (try? context.fetch(FetchDescriptor<SavedLocation>())) ?? []
        guard !locations.isEmpty else { return }

        let existingAssignments = (try? context.fetch(FetchDescriptor<LocationAssignment>())) ?? []
        var assignedKeys = Set(existingAssignments.map { $0.itemKey })

        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []

        let candidateTitles = events.map { $0.title } + reminders.map { $0.title }

        var candidateItems: [String] = []
        var seenKeys = Set<String>()

        for title in candidateTitles {
            let key = normalize(title)
            guard !key.isEmpty, !assignedKeys.contains(key), !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            candidateItems.append(title)
        }

        guard !candidateItems.isEmpty else {
            markSeeded(locations)
            return
        }

        var remainingItems: [String] = []

        for item in candidateItems {
            if let location = deterministicMatch(item: item, locations: locations) {
                assign(item: item, to: location, userConfirmed: false)
                assignedKeys.insert(normalize(item))
            } else {
                remainingItems.append(item)
            }
        }

        if !remainingItems.isEmpty {
            await classify(items: remainingItems, locations: locations, priorAssignments: existingAssignments)
        }

        markSeeded(locations)
        try? context.save()

    }

    /// Records the user moving a reminder to a different place, or
    /// confirming where it belongs — becomes a permanent override and a
    /// ground-truth example the classifier follows for similar items later.
    func confirmAssignment(itemTitle: String, location: SavedLocation) {

        let key = normalize(itemTitle)

        let descriptor = FetchDescriptor<LocationAssignment>(
            predicate: #Predicate { $0.itemKey == key }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.locationID = location.id
            existing.userConfirmed = true
            existing.updatedAt = .now
        } else {
            context.insert(
                LocationAssignment(itemKey: key, locationID: location.id, userConfirmed: true)
            )
        }

        try? context.save()

    }

    // MARK: - Classification

    private func classify(
        items: [String],
        locations: [SavedLocation],
        priorAssignments: [LocationAssignment]
    ) async {

        let priorCorrections = priorAssignments
            .filter { $0.userConfirmed }
            .compactMap { assignment -> (item: String, locationName: String)? in
                guard let location = locations.first(where: { $0.id == assignment.locationID }) else {
                    return nil
                }
                return (assignment.itemKey, location.name)
            }

        let locationTuples = locations.map { (name: $0.name, address: $0.address) }

        guard let promptText = contextBuilder.buildClassificationContext(
            locations: locationTuples,
            items: items,
            priorCorrections: priorCorrections
        ) else { return }

        guard let suggestions = try? await foundationModel.classifyItems(forPromptText: promptText) else {
            return
        }

        for suggestion in suggestions {

            guard suggestion.locationName.lowercased() != "none" else { continue }

            guard let location = locations.first(where: {
                $0.name.caseInsensitiveCompare(suggestion.locationName) == .orderedSame
            }) else { continue }

            assign(item: suggestion.itemTitle, to: location, userConfirmed: false)

        }

    }

    // MARK: - Deterministic matching

    private func deterministicMatch(item: String, locations: [SavedLocation]) -> SavedLocation? {

        let itemKeywords = keywords(from: item)
        guard !itemKeywords.isEmpty else { return nil }

        for location in locations {

            if !keywords(from: location.name).isDisjoint(with: itemKeywords) {
                return location
            }

            if let address = location.address, !keywords(from: address).isDisjoint(with: itemKeywords) {
                return location
            }

        }

        return nil

    }

    private func keywords(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !Self.stopwords.contains($0) }
        return Set(words)
    }

    // MARK: - Writing

    private func assign(item: String, to location: SavedLocation, userConfirmed: Bool) {

        let key = normalize(item)

        context.insert(
            LocationAssignment(itemKey: key, locationID: location.id, userConfirmed: userConfirmed)
        )

        context.insert(
            LocationReminder(locationID: location.id, text: item, isAISeeded: true)
        )

    }

    private func markSeeded(_ locations: [SavedLocation]) {
        for location in locations where !location.hasBeenSeeded {
            location.hasBeenSeeded = true
        }
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
