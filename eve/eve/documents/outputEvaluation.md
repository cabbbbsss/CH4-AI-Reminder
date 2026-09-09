# AI Evaluation Notes & Judgment

## Overview of the New Algorithm
The new evaluation algorithm (Jaccard Index with NLP preprocessing + 50% penalty for missing the core message) is now **highly accurate and working exactly as intended**. It is no longer giving "free passes" for simply formatting the JSON correctly. Instead, it brutally grades the model on whether it successfully injected the expected real-world facts into its sentences.

Let's break down the latest test run.

---

### Scenario 1: Busy Executive
*   **Accuracy:** 62.2%
*   **Expected:** "Print the Q3 financial reports for the meeting in Conference Room A."
*   **Actual:** "Review Q3 financial reports before the meeting."
*   **Judgment:** The score of 62.2% is a perfect reflection of this output. The AI successfully identified the context (Q3 financial reports, meeting), which gives it a passing grade. However, it failed on two fronts: it said "Review" instead of "Print", and it completely forgot to mention "Conference Room A". The algorithm rightfully docked ~38% of the points for missing these critical specifics.

### Scenario 2: Student Morning
*   **Accuracy:** 57.2%
*   **Expected:** "Bring your student ID, #2 pencils, and a calculator to Room 402."
*   **Actual:** "Bring #2 pencils and calculator to the exam."
*   **Judgment:** Again, the algorithm nailed this. The AI got the tools right (pencils, calculator), but it missed the "student ID" and the location ("Room 402"). A score in the high 50s perfectly represents a "C-grade" reminder—helpful, but incomplete.

### Scenario 3: Weekend Hiker
*   **Accuracy:** 20.0%
*   **Expected:** "Don't forget to pack your sunglasses and at least 2 liters of water."
*   **Actual:** "Bring sunglasses."
*   **Judgment:** This is the most beautiful demonstration of the new algorithm working! The AI was incredibly lazy here. Not only did it pick the wrong category (Actionable instead of Insight), but it completely ignored the "2 liters of water" insight. Because the body text was so short and missed more than 70% of the expected keywords, the new **Hallucination/Laziness Penalty** kicked in, instantly slicing the AI's score in half to a failing 20.0%.

---

## Does the Algorithm Need Improvement?
**No.** The Swift evaluation algorithm is now a robust, strict judge. It does not need any more tweaking. It is successfully catching when the AI misses details or gets lazy.

## What Needs Improvement?
The low scores are no longer a math problem—they are a **Prompt Engineering** problem. To get these scores from the 60s up to the 90s, we need to update the instructions in `FoundationModelService.swift` to force the AI to be more thorough. 

**Next Steps for Prompt Improvement:**
1.  **Force Location Injection:** Add a strict rule to the prompt: *"If an event location or room number is provided in the context, you MUST include it in the body."* (This will fix the missing Room 402 and Conference Room A).
2.  **Combine Insights:** Add a strict rule: *"If multiple relevant insights or pending reminders exist for an event, you MUST combine them into a single sentence."* (This will force the AI to combine the sunglasses AND the water into one reminder).
