//
//  KnowledgeStore.swift
//  Eve
//

import Foundation

/// Eve's knowledge corpus: what a *kind* of activity typically needs.
///
/// The user's calendar says a gym session is happening; these say it implies
/// gear. Retrieved per event and appended to the prep prompt — never prepended
/// wholesale, because the on-device window is 4096 tokens shared with the
/// instructions, the schema and the response (TN3193).
///
/// ## Why matching is lexical
///
/// This was first built on sentence embeddings, and it did not work. Measured
/// on the real corpus:
///
/// - `NLContextualEmbedding`, mean-pooled, scored *every* pair between 0.61 and
///   0.67 regardless of meaning — and ranked the meeting chunk above the gym
///   chunk for the query "Gym".
/// - `NLEmbedding.sentenceEmbedding` scored the correct meeting chunk (-0.393)
///   *below* an unrelated vet chunk (-0.296) for "Team standup".
///
/// Neither is separable, for one root reason: calendar titles are one or two
/// words ("Gym", "Sleep", "Wind Down"), and sentence embeddings need sentences.
/// The visible symptom was a Sleep event being told to check its virtual
/// meeting software — the nearest chunk is always *some* chunk, and with a
/// floor below the noise band, every event retrieved something.
///
/// Explicit triggers are deterministic, inspectable, and testable without a
/// device. At a few dozen chunks that is the right tool; a vector index was
/// over-engineering even before it turned out to be wrong.
struct KnowledgeStore {

    struct Fact: Decodable {
        let key: String
        let topic: String
        let triggers: [String]
        let text: String
    }

    private struct Corpus: Decodable {
        let version: Int
        let facts: [Fact]
    }

    /// Parsed once per launch. The file is a few kilobytes and never changes at
    /// runtime, so there is nothing to persist and no index to rebuild — the
    /// SwiftData model this used to need existed only to store vectors.
    private static let facts: [Fact] = {
        guard let url = Bundle.main.url(forResource: "knowledge", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONDecoder().decode(Corpus.self, from: data)
        else {
            assertionFailure("knowledge.json missing or malformed — knowledge retrieval is disabled")
            return []
        }
        return corpus.facts
    }()

    /// Facts whose triggers appear in `subjectKeywords`, best first.
    ///
    /// Ranked by how many triggers matched, so a "Gym workout" event prefers a
    /// fact keyed on both words over one keyed on either. Returns empty for an
    /// event the corpus says nothing about — "Sleep" matches no trigger, and
    /// nothing is the correct answer there.
    ///
    /// - Parameter subjectKeywords: already lowercased and stopword-stripped by
    ///   `OutputGrounding.contentTerms`, so matching is a set intersection.
    static func facts(matching subjectKeywords: Set<String>, limit: Int = 3) -> [Fact] {

        guard !subjectKeywords.isEmpty else { return [] }

        let scored: [(fact: Fact, hits: Int)] = facts.compactMap { fact in
            let hits = fact.triggers.reduce(into: 0) { total, trigger in
                if subjectKeywords.contains(trigger) { total += 1 }
            }
            return hits > 0 ? (fact, hits) : nil
        }

        return scored
            .sorted { $0.hits > $1.hits }
            .prefix(limit)
            .map(\.fact)

    }

}
