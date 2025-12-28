import Foundation

/// Stub summarizer that returns mock responses for development/testing
final class StubSummarizer: Summarizer {

    let id = "stub"
    let name = "Mock Summarizer"
    var isAvailable: Bool { true }

    /// Simulated processing delay
    private let simulatedDelay: TimeInterval = 1.5

    func summarize(transcript: String, existingSummary: SummarizerOutput?) async throws -> SummarizerOutput {
        // Simulate processing time
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        // Generate a mock summary based on transcript length and content
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count

        // Extract potential title from first few words
        let titleWords = Array(words.prefix(6))
        let title = existingSummary?.title ?? (titleWords.isEmpty ? "Untitled Thought" : titleWords.joined(separator: " ") + "...")

        // Generate summary
        let summary: String
        if let existing = existingSummary {
            summary = existing.summary + " Additionally, the speaker elaborated on their thoughts with \(wordCount) more words of context."
        } else {
            summary = "A \(wordCount)-word brainstorming session covering various ideas and considerations. The speaker explored multiple angles on the topic."
        }

        // Generate bullets based on word count
        let bulletCount = min(5, max(2, wordCount / 20))
        var bullets = existingSummary?.bullets ?? []
        for i in 0..<bulletCount {
            if i < words.count / 10 {
                let startIndex = i * 10
                let endIndex = min(startIndex + 8, words.count)
                let bulletWords = Array(words[startIndex..<endIndex])
                bullets.append("Point about: " + bulletWords.joined(separator: " "))
            }
        }

        // Generate mock todos
        var todos = existingSummary?.todos ?? []
        if transcript.lowercased().contains("need to") || transcript.lowercased().contains("should") {
            todos.append(TodoItem.DTO(text: "Follow up on discussed action items", dueDate: nil, priority: 2))
        }
        if transcript.lowercased().contains("call") || transcript.lowercased().contains("email") || transcript.lowercased().contains("contact") {
            todos.append(TodoItem.DTO(text: "Reach out to mentioned contacts", dueDate: nil, priority: 1))
        }
        if transcript.lowercased().contains("meeting") || transcript.lowercased().contains("schedule") {
            todos.append(TodoItem.DTO(text: "Schedule discussed meeting", dueDate: nil, priority: 2))
        }

        return SummarizerOutput(
            title: title,
            summary: summary,
            bullets: bullets,
            todos: todos,
            questions: nil,
            decision: nil
        )
    }

    func runGuidedThinking(
        transcript: String,
        previousQuestions: [String],
        previousAnswers: [String]
    ) async throws -> SummarizerOutput {
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        let questionNumber = previousQuestions.count + 1
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Generate a follow-up question based on context
        let questions: [String]
        switch questionNumber {
        case 1:
            questions = ["What specific outcome are you hoping to achieve with this?"]
        case 2:
            questions = ["What potential obstacles do you foresee?"]
        case 3:
            questions = ["Who else might be affected by or involved in this?"]
        case 4:
            questions = ["What would success look like in 6 months?"]
        default:
            questions = ["Is there anything else you'd like to explore about this topic?"]
        }

        // Build updated summary incorporating answers
        var summaryParts = ["Initial thoughts covered \(words.count) words."]
        for (i, answer) in previousAnswers.enumerated() {
            if i < previousQuestions.count {
                let answerWords = answer.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                summaryParts.append("In response to '\(previousQuestions[i].prefix(30))...', explored \(answerWords.count) words of additional context.")
            }
        }

        return SummarizerOutput(
            title: "Guided Exploration Session",
            summary: summaryParts.joined(separator: " "),
            bullets: [
                "Initial brainstorming captured",
                "Clarifying questions explored",
                "Deeper insights developing"
            ],
            todos: [
                TodoItem.DTO(text: "Review and refine thoughts after session", dueDate: nil, priority: 3)
            ],
            questions: questions,
            decision: nil
        )
    }

    func analyzeDecision(transcript: String) async throws -> SummarizerOutput {
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        // Extract some context from transcript
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let hasOr = transcript.lowercased().contains(" or ")

        // Mock decision analysis
        let decision = DecisionData(
            recommendation: "Based on the information provided, consider gathering more data before making a final decision. The key factors appear balanced.",
            confidence: 0.65,
            pros: [
                .init(text: "Potential for positive outcomes mentioned", weight: 3),
                .init(text: "Aligns with stated goals", weight: 2),
                .init(text: "Timing seems appropriate", weight: 2)
            ],
            cons: [
                .init(text: "Some uncertainty in the details", weight: 2),
                .init(text: "May require additional resources", weight: 3),
                .init(text: "Potential risks not fully explored", weight: 2)
            ],
            unknowns: [
                "Long-term implications",
                "Impact on other priorities",
                "External factors that could change"
            ]
        )

        return SummarizerOutput(
            title: hasOr ? "Decision: Weighing Options" : "Decision Analysis",
            summary: "Analysis of a decision with \(words.count) words of context. Multiple factors are being considered with a balanced view of pros and cons.",
            bullets: [
                "Key factors have been identified",
                "Trade-offs are being evaluated",
                "Additional information may help clarify"
            ],
            todos: [
                TodoItem.DTO(text: "Gather more information on unknowns", dueDate: nil, priority: 1),
                TodoItem.DTO(text: "Discuss with relevant stakeholders", dueDate: nil, priority: 2)
            ],
            questions: [
                "What additional information would help you decide?",
                "What's your timeline for making this decision?"
            ],
            decision: decision
        )
    }
}
