//
//  OutputGrounding.swift
//  Eve
//

import Foundation

/// Holds the model's output to the context it was actually given.
///
/// Some of Eve's instructions already demand this in words — the prep prompt
/// says "Every item must be traceable to something explicitly stated above"
/// — but an instruction is a request, not a guarantee. This is the same move
/// `InsightManager` makes for user-confirmed beliefs and `classifyPlaceIcon`
/// makes for icon names: state the rule in the prompt, then enforce it in
/// code, and treat output that breaks it as absent rather than as content.
///
/// Deliberately **lexical only**, no embeddings. A semantic check would pass
/// exactly the failures this exists to catch: "bring workout gear" sits close
/// to "Gym" in vector space whether or not anything about gear was ever in the
/// context. Nearness to the subject is what plausible invention looks like.
/// Where that inference is wanted, the answer is to not run the gate — see
/// `suggestLocationReminder`, which is inferential by design.
enum OutputGrounding {

    // MARK: - Tokenising
    //
    // The single tokeniser for both retrieval and this gate. It has to be:
    // grounding compares terms `ReminderContextBuilder` produced against terms
    // produced here, so two tokenisers that drifted apart would show up as the
    // gate quietly discarding good output.

    static let stopwords: Set<String> = [
        "a", "an", "the", "at", "in", "on", "for", "to", "of", "and", "with",
        "is", "are", "this", "that", "your", "you", "me", "my", "it", "be",
        "do", "not", "no", "yes", "today", "tomorrow", "day", "time"
    ]

    /// Lowercased content words, stopwords removed.
    static func contentTerms(of text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !stopwords.contains($0) }
        )
    }

    /// Words that carry no evidence on their own, on top of `stopwords`.
    ///
    /// Every prep item is phrased as an instruction, so they nearly all
    /// contain "bring", "check", or "pack" — and so does any reminder that
    /// reached the context. Counting those as a match would ground "bring your
    /// notes" on a context that only ever said "bring laptop", which is the
    /// substitution the gate is here to catch. They stay out of `stopwords`
    /// because retrieval *does* want them: a reminder saying "pack passport"
    /// is a genuine lexical signal when matching an event.
    private static let evidenceFreeWords: Set<String> = [
        "bring", "check", "prepare", "prep", "pack", "take", "get", "grab",
        "remember", "forget", "don", "ready", "before", "make", "sure",
        "need", "needs", "have", "any", "some", "all", "out", "up", "off"
    ]

    // MARK: - The gate

    /// Keeps only the items that name something the context actually
    /// contained; returns what it dropped so callers can log it.
    ///
    /// An item survives on one shared evidence-bearing term. That's a low bar
    /// on purpose — the goal is to catch output about subjects the model was
    /// never told about, not to police wording. Raising it to two terms drops
    /// correct single-noun items like "Passport".
    /// - Parameter subjectTerms: content words of the event *title* only. An
    ///   item saying nothing beyond the title is dropped as vacuous — a
    ///   "Breakfast" event produced the prep item "Bring breakfast", which is
    ///   grounded, correctly formed, and completely useless. Notes are excluded
    ///   from this set on purpose: they are long enough that a subset test
    ///   against them would start discarding good items.
    static func filter(
        _ items: [String],
        groundedIn terms: Set<String>,
        notRestating subjectTerms: Set<String> = []
    ) -> (kept: [String], dropped: [String]) {

        // Nothing to check against — an empty context can't disprove anything,
        // and dropping everything here would silently disable the feature on
        // exactly the sparse installs it's least safe to be wrong about.
        guard !terms.isEmpty else { return (items, []) }

        let evidence = terms.subtracting(evidenceFreeWords)

        guard !evidence.isEmpty else { return (items, []) }

        var kept: [String] = []
        var dropped: [String] = []

        for item in items {

            let itemTerms = contentTerms(of: item).subtracting(evidenceFreeWords)

            if itemTerms.isDisjoint(with: evidence) {
                dropped.append(item)
                continue
            }

            // Says nothing the title didn't already say.
            if !subjectTerms.isEmpty, itemTerms.isSubset(of: subjectTerms) {
                dropped.append(item)
                continue
            }

            kept.append(item)

        }

        return (kept, dropped)

    }

    /// `filter`, with the dropped items logged in debug builds.
    ///
    /// The log is the tuning instrument. `semanticDistanceLimit` in
    /// `ReminderContextBuilder` and the bar above are both starting points;
    /// watching what gets dropped on a real account is how you find out
    /// whether retrieval is too narrow or the gate too tight.
    static func filterLogging(
        _ items: [String],
        groundedIn terms: Set<String>,
        notRestating subjectTerms: Set<String> = [],
        label: String
    ) -> [String] {

        let result = filter(items, groundedIn: terms, notRestating: subjectTerms)

        #if DEBUG
        for item in result.dropped {
            print("[Eve/grounding] \(label): dropped ungrounded item — \"\(item)\"")
        }
        #endif

        return result.kept

    }

}
