//
//  QuestionShape.swift
//  Eve
//

import Foundation

/// Decides whether a generated onboarding question is actually answerable with
/// the two buttons the screen shows.
///
/// `OnboardingQuestionsView` renders Yes and No and nothing else, so a question
/// that isn't closed has no correct answer. The model shipped
/// "Do you prefer to work remotely or in an office?" — which breaks no rule the
/// prompt stated at the time: it isn't compound, and it uses none of the
/// when/what/where/how words the instructions ban. It simply offers a choice.
///
/// The instructions now say so explicitly, but a small model asked for a closed
/// question will still occasionally write an open one, and a bad question is
/// answered into `QuestionAnswer` and then re-enters every later prompt as
/// though it were fact. That makes this the wrong place to rely on the model
/// complying — the same reasoning as `InsightShape`.
enum QuestionShape {

    /// Auxiliaries and modals a closed question opens with. A question that
    /// starts with anything else isn't shaped for Yes/No.
    private static let closedOpenings: Set<String> = [
        "do", "does", "did",
        "is", "are", "am", "was", "were",
        "have", "has", "had",
        "will", "would", "shall", "should",
        "can", "could", "may", "might"
    ]

    /// Interrogatives that demand an answer other than yes or no. Matched as
    /// whole words, so "however" doesn't read as "how".
    private static let openInterrogatives: Set<String> = [
        "what", "when", "where", "how", "which", "who", "whom", "whose", "why"
    ]

    /// Words that turn a question into a choice between alternatives.
    ///
    /// Only rejected alongside a literal "or": "Do you prefer mornings?" is a
    /// perfectly good yes/no question, and "Do you have a cat or a dog?" is
    /// answerable even if it's clumsy. It's the offered alternative — prefer X
    /// *or* Y — that has no yes/no answer.
    private static let choiceMarkers: Set<String> = ["prefer", "rather"]

    /// Long enough to be specific, short enough to read at a glance.
    private static let maximumWords = 18

    /// True when `question` can be answered by tapping Yes or No.
    static func isYesNo(_ question: String) -> Bool {
        reasonToReject(question) == nil
    }

    /// Why this question can't be shown, or nil when it's fine.
    static func reasonToReject(_ question: String) -> String? {

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "empty" }
        guard trimmed.hasSuffix("?") else { return "not phrased as a question" }

        let words = trimmed.lowercased().split { !$0.isLetter }.map(String.init)

        guard let opening = words.first else { return "empty" }

        guard closedOpenings.contains(opening) else {
            return "opens with \"\(opening)\", not a yes/no auxiliary"
        }

        guard words.count <= maximumWords else {
            return "too long to answer at a glance"
        }

        if let interrogative = words.first(where: { openInterrogatives.contains($0) }) {
            return "open-ended (\"\(interrogative)\")"
        }

        if words.contains("or"), words.contains(where: { choiceMarkers.contains($0) }) {
            return "offers a choice rather than a yes or no"
        }

        return nil
    }

    /// The questions worth showing: closed, unique, and — when the user has a
    /// calendar to draw on — actually about it.
    ///
    /// Returning fewer than the model produced (or none) is the intended
    /// outcome. `OnboardingQuestionsView` falls back to
    /// `AILearningEngine.fallbackQuestions`, which are hand-written and all
    /// closed, so an empty result degrades to something answerable rather than
    /// to nonsense.
    ///
    /// - Parameter calendarTerms: content words from the user's own events.
    ///   Empty when there is no calendar data, in which case the grounding
    ///   check is skipped — there is nothing to be about.
    static func usable(
        _ questions: [OnboardingQuestion],
        groundedIn calendarTerms: Set<String>
    ) -> [OnboardingQuestion] {

        var seen = Set<String>()

        return questions.filter { candidate in

            guard reasonToReject(candidate.question) == nil else { return false }

            let key = candidate.question
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard seen.insert(key).inserted else { return false }

            guard !calendarTerms.isEmpty else { return true }

            return !OutputGrounding
                .contentTerms(of: candidate.question)
                .isDisjoint(with: calendarTerms)
        }
    }
}
