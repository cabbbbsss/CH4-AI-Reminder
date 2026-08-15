//
//  InsightShape.swift
//  Eve
//

import Foundation

/// Decides whether a generated sentence is a *belief* about the user, as
/// opposed to a reminder, a piece of advice, or a passing observation.
///
/// `OutputGrounding` asks a different question — whether output traces back to
/// the context — and cannot cover this one. "Make sure your Tennis Location is
/// comfortable and quiet" is perfectly grounded: "tennis" and "location" are
/// both in the context it was given. It is still not a belief, and storing it
/// as one put advice into the user's Insights list at 100% confidence.
///
/// That happened because a single model call used to emit both the
/// notification body and the proposed beliefs; in reminder-writing mode it
/// filled both fields with the same sentence. Splitting the calls fixes the
/// cause, but the shape check stays: a small model asked for a belief will
/// still sometimes write a suggestion, and beliefs persist and re-enter every
/// later prompt, so this is the wrong place to rely on the model complying.
///
/// The `@Guide` on `ProposedInsight.value` already asks for exactly this shape
/// — a self-contained second-person sentence. This enforces in code what that
/// description merely requests, the same move `InsightManager` makes for
/// user-confirmed beliefs.
enum InsightShape {

    /// Openings a durable belief starts with. Checking this alone rejects every
    /// imperative — "Make sure…", "Take…", "Don't forget…" — because none of
    /// them begin with the second person, so no separate verb list is needed.
    private static let secondPersonOpenings: Set<String> = [
        "you", "youre", "your", "yours"
    ]

    /// Phrasing that marks a suggestion rather than a statement of fact.
    ///
    /// Narrow on purpose: "helpful to" rather than "helpful", so a genuine
    /// belief like "You find music helpful for focus" survives while "You might
    /// find it helpful to take deep breaths" does not.
    private static let adviceMarkers: [String] = [
        "should", "might", "could", "may want", "helpful to",
        "try to", "make sure", "remember to", "consider", "be sure"
    ]

    /// Phrasing that describes a passing moment. A belief has to still be true
    /// tomorrow; "You're heading to your usual lunch spot" is false within the
    /// hour and would keep re-entering prompts as though it were durable.
    private static let transientMarkers: [String] = [
        "heading to", "right now", "currently", "today", "tonight",
        "this morning", "this afternoon", "this evening", "at the moment"
    ]

    private static let minimumWords = 3
    private static let maximumWords = 20

    /// True when `value` reads as a durable, second-person belief.
    static func isBelief(_ value: String) -> Bool {
        reasonToReject(value) == nil
    }

    /// Why `value` isn't a belief, or nil if it is. Separate from `isBelief` so
    /// callers can log *which* rule fired — with four rules, "rejected" alone
    /// isn't enough to tune them.
    static func reasonToReject(_ value: String) -> String? {

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)

        guard words.count >= minimumWords else { return "too short" }
        guard words.count <= maximumWords else { return "too long" }

        let firstWord = words[0]
            .lowercased()
            .filter { $0.isLetter }

        guard secondPersonOpenings.contains(firstWord) else {
            return "not second person (starts with \"\(words[0])\")"
        }

        let lowered = trimmed.lowercased()

        if let marker = adviceMarkers.first(where: { lowered.contains($0) }) {
            return "advice, not a belief (\"\(marker)\")"
        }

        if let marker = transientMarkers.first(where: { lowered.contains($0) }) {
            return "transient, not durable (\"\(marker)\")"
        }

        return nil

    }

}
