import Foundation

/// Protocol defining the summarizer interface
/// Implementations can be local (llama.cpp, MLX) or remote (API-based)
protocol Summarizer {

    /// Unique identifier for this summarizer
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Whether this summarizer is available (model loaded, API reachable, etc.)
    var isAvailable: Bool { get }

    /// Summarize a transcript in ramble mode
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - existingSummary: Optional existing summary for appending
    /// - Returns: Structured summary output
    func summarize(transcript: String, existingSummary: SummarizerOutput?) async throws -> SummarizerOutput

    /// Run guided thinking - generate follow-up questions
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - previousQuestions: Questions already asked
    ///   - previousAnswers: Answers to previous questions
    /// - Returns: Updated summary with new questions
    func runGuidedThinking(
        transcript: String,
        previousQuestions: [String],
        previousAnswers: [String]
    ) async throws -> SummarizerOutput

    /// Analyze a decision from transcript
    /// - Parameter transcript: The raw transcript containing the decision question
    /// - Returns: Summary with decision analysis (pros/cons/recommendation)
    func analyzeDecision(transcript: String) async throws -> SummarizerOutput
}

// MARK: - Summarizer Type

enum SummarizerType: String, Codable, CaseIterable, Identifiable {
    case stub = "stub"
    case gemini = "gemini"
    case remote = "remote"
    case onDevice = "onDevice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stub: return "Mock (Development)"
        case .gemini: return "Gemini Flash"
        case .remote: return "OpenAI/Anthropic API"
        case .onDevice: return "On-Device (Local)"
        }
    }

    var description: String {
        switch self {
        case .stub: return "Returns simulated responses for testing"
        case .gemini: return "Google Gemini 2.5 Flash-Lite for fast summarization"
        case .remote: return "Uses OpenAI or Anthropic API"
        case .onDevice: return "Runs locally using llama.cpp"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .stub, .onDevice: return false
        case .gemini, .remote: return true
        }
    }
}

// MARK: - Summarizer Factory

/// Factory for creating summarizer instances
enum SummarizerFactory {

    /// Create a summarizer of the specified type
    static func create(type: SummarizerType, config: SummarizerConfig = .default) -> Summarizer {
        switch type {
        case .stub:
            return StubSummarizer()
        case .gemini:
            let apiKey = config.apiKey ?? KeychainHelper.getGeminiAPIKey() ?? ""
            return GeminiSummarizer(apiKey: apiKey, modelName: config.modelName ?? "gemini-2.0-flash-lite")
        case .remote:
            return RemoteSummarizer(config: config)
        case .onDevice:
            // Future: return OnDeviceSummarizer(config: config)
            // For now, fall back to stub
            return StubSummarizer()
        }
    }

    /// Create a summarizer from current settings
    static func fromSettings() -> Summarizer {
        let typeRaw = UserDefaults.standard.string(forKey: "summarizerType") ?? SummarizerType.stub.rawValue
        let type = SummarizerType(rawValue: typeRaw) ?? .stub

        switch type {
        case .stub:
            return StubSummarizer()

        case .gemini:
            if let summarizer = GeminiSummarizer.fromSettings() {
                return summarizer
            }
            return StubSummarizer() // Fallback if no API key

        case .remote:
            let apiKey = KeychainHelper.getAPIKey() ?? ""
            let endpoint = UserDefaults.standard.string(forKey: "apiEndpoint") ?? ""
            let config = SummarizerConfig(
                apiEndpoint: endpoint.isEmpty ? nil : endpoint,
                apiKey: apiKey.isEmpty ? nil : apiKey,
                modelName: nil,
                maxTokens: 2048,
                temperature: 0.7
            )
            return RemoteSummarizer(config: config)

        case .onDevice:
            return StubSummarizer() // Fallback for now
        }
    }
}

// MARK: - Summarizer Configuration

struct SummarizerConfig: Codable {
    var apiEndpoint: String?
    var apiKey: String?
    var modelName: String?
    var maxTokens: Int
    var temperature: Double

    static var `default`: SummarizerConfig {
        SummarizerConfig(
            apiEndpoint: nil,
            apiKey: nil,
            modelName: nil,
            maxTokens: 2048,
            temperature: 0.7
        )
    }
}

// MARK: - Prompt Templates

enum SummarizerPrompts {

    static func ramblePrompt(transcript: String, existingSummary: SummarizerOutput?) -> String {
        var prompt = """
        You are analyzing a voice transcript from a thinking/brainstorming session. Extract the key information and structure it clearly.

        TRANSCRIPT:
        \(transcript)
        """

        if let existing = existingSummary {
            prompt += """


            EXISTING SUMMARY TO UPDATE:
            Title: \(existing.title)
            Summary: \(existing.summary)
            Bullets: \(existing.bullets.joined(separator: "; "))
            """
        }

        prompt += """


        Respond with a JSON object in this exact format:
        {
            "title": "A brief title (max 50 chars)",
            "summary": "A concise 1-3 sentence summary",
            "bullets": ["Key point 1", "Key point 2", ...],
            "todos": [{"text": "Action item", "dueDate": null, "priority": 1}],
            "questions": null,
            "decision": null
        }

        Rules:
        - Title should capture the main topic
        - Summary should be concise but complete
        - Bullets should be the key points/ideas (3-7 items)
        - Todos should be actionable items mentioned (with priority 1=high, 2=medium, 3=low)
        - Only include todos if specific actions were mentioned
        - Respond ONLY with valid JSON, no other text
        """

        return prompt
    }

    static func guidedPrompt(
        transcript: String,
        previousQuestions: [String],
        previousAnswers: [String]
    ) -> String {
        var prompt = """
        You are a thinking coach helping someone develop their ideas. Analyze their thoughts and ask clarifying questions to help them think deeper.

        ORIGINAL TRANSCRIPT:
        \(transcript)
        """

        if !previousQuestions.isEmpty {
            prompt += "\n\nPREVIOUS QUESTIONS AND ANSWERS:"
            for (i, question) in previousQuestions.enumerated() {
                prompt += "\nQ\(i+1): \(question)"
                if i < previousAnswers.count {
                    prompt += "\nA\(i+1): \(previousAnswers[i])"
                }
            }
        }

        prompt += """


        Respond with a JSON object:
        {
            "title": "Updated title",
            "summary": "Updated summary incorporating new insights",
            "bullets": ["Updated key points"],
            "todos": [{"text": "Action item", "dueDate": null, "priority": null}],
            "questions": ["One thoughtful follow-up question"],
            "decision": null
        }

        Rules:
        - Generate 1-2 clarifying questions that will help develop the idea
        - Questions should be specific and thought-provoking
        - Update summary and bullets based on all information
        - Respond ONLY with valid JSON
        """

        return prompt
    }

    static func decisionPrompt(transcript: String) -> String {
        """
        You are a decision analysis assistant. The user is trying to make a decision. Analyze the situation and provide a structured analysis.

        TRANSCRIPT:
        \(transcript)

        Respond with a JSON object:
        {
            "title": "Brief description of the decision",
            "summary": "Summary of the decision context",
            "bullets": ["Key factors to consider"],
            "todos": [{"text": "Action to take before deciding", "dueDate": null, "priority": null}],
            "questions": ["What additional information would help?"],
            "decision": {
                "recommendation": "Your recommendation with reasoning",
                "confidence": 0.0 to 1.0,
                "pros": [{"text": "Pro argument", "weight": 1-5}],
                "cons": [{"text": "Con argument", "weight": 1-5}],
                "unknowns": ["Things that could change the analysis"]
            }
        }

        Rules:
        - Be balanced and objective
        - Weight reflects importance (1=minor, 5=critical)
        - Confidence reflects how clear the decision is
        - Include at least 2 pros and 2 cons
        - Unknowns are factors that need more information
        - Respond ONLY with valid JSON
        """
    }
}
