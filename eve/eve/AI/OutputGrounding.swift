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

    /// Folds a plural onto its singular, so both sides of a comparison land on
    /// the same token.
    ///
    /// Measured need: an event titled "Mountain Trail Hike" retrieved none of
    /// the user's beliefs, because the belief said "morning hikes" — a
    /// relevant, correctly-stored belief lost to one letter.
    ///
    /// Anything that compares against the output of `contentTerms` must be run
    /// through this too, or it silently stops matching: `KnowledgeStore`'s
    /// triggers ("pills", "groceries", "teams") and the place synonym sets
    /// ("chores", "kids") are literals that would otherwise never be hit again.
    ///
    /// The `count > 3` guard is why "bus" and "gas" survive intact, and the
    /// `ss` guard is why "pass" does not become "pas".
    ///
    // ponytail: plural strip only, not linguistics — "glasses" becomes
    // "glasse", which is harmless because every caller runs this same function
    // and only ever compares results with each other. Reach for NLTagger
    // `.lemma` if a real miss ever traces back to tense or an -ing form.
    nonisolated static func stem(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// Lowercased content words, stopwords removed, plurals folded.
    ///
    /// Stopwords are matched before stemming, on the raw word — they are
    /// function words with no plurals, so the order costs nothing and keeps
    /// that list readable as written.
    static func contentTerms(of text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !stopwords.contains($0) }
                .map(stem)
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
    private static let evidenceFreeWords: Set<String> = Set([
        "bring", "check", "prepare", "prep", "pack", "take", "get", "grab",
        "remember", "forget", "don", "ready", "before", "make", "sure",
        "need", "needs", "have", "any", "some", "all", "out", "up", "off"
    ].map(stem))

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

        // An empty `terms` disables the disjointness test only — it can't
        // disprove anything, and dropping everything would silently disable
        // the feature on exactly the sparse installs it's least safe to be
        // wrong about. Callers pass an empty set deliberately: see
        // `PreparationPrompt.hasRetrievedContext`.
        //
        // The restatement rule below still runs. It used to be skipped here
        // too, by an early return, which was backwards — with no retrieved
        // context the vacuous items are the *only* ones the test above would
        // have let through.
        let evidence = terms.subtracting(evidenceFreeWords)

        var kept: [String] = []
        var dropped: [String] = []

        for item in items {

            let itemTerms = contentTerms(of: item).subtracting(evidenceFreeWords)

            if !evidence.isEmpty, itemTerms.isDisjoint(with: evidence) {
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

    // MARK: - Self-check
    //
    // There is no test target, and the rules above have each regressed once
    // already, so the three cases that matter run at launch in debug builds.

    #if DEBUG
    static func selfCheck() {

        // Plural and singular have to reach the same token — the miss that
        // `stem` exists to fix — without flattening the words it must not touch.
        assert(contentTerms(of: "morning hikes").contains("hike"), "stem: plural not folded")
        assert(contentTerms(of: "Mountain Trail Hike").contains("hike"), "stem: singular altered")
        assert(contentTerms(of: "board meetings") == contentTerms(of: "Board Meeting"),
               "stem: plural and singular disagree")
        assert(contentTerms(of: "bus pass").isSuperset(of: ["bus", "pass"]),
               "stem: over-eager, short words and -ss must survive")

        // Both sets are built the way callers build them — through
        // `contentTerms` — rather than written as literals. Literals drifted
        // the moment `stem` landed: the check hand-wrote "tennis" while every
        // real caller was by then producing "tenni".
        let tennis = contentTerms(of: "Tennis")

        // Invention is dropped while there is retrieved context to disprove it.
        assert(
            filter(["Bring your racket"], groundedIn: contentTerms(of: "gym towel")).kept.isEmpty,
            "grounding: ungrounded item survived a context that disproved it"
        )

        // With no retrieved context the same item is admitted, rather than the
        // gate collapsing into "the item must echo the event title".
        assert(
            filter(["Bring your racket"], groundedIn: [], notRestating: tennis).kept.count == 1,
            "grounding: gate still rewarding restatement on an unretrieved event"
        )

        // ...but the vacuous item stays dropped. This is the case the early
        // return used to get backwards.
        assert(
            filter(["Bring tennis"], groundedIn: [], notRestating: tennis).dropped.count == 1,
            "grounding: restatement admitted when the context was empty"
        )

    }
    #endif

    /// `filter`, with the dropped items logged in debug builds.
    ///
    /// The log is the tuning instrument. The shared-term match in
    /// `ReminderContextBuilder.relevance(of:to:)` and the bar above are both
    /// starting points; watching what gets dropped on a real account is how
    /// you find out whether retrieval is too narrow or the gate too tight.
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
