import Foundation

/// Remote API-based summarizer
/// Configurable to work with various LLM API providers
final class RemoteSummarizer: Summarizer {

    let id = "remote"
    let name = "Remote API"

    private let config: SummarizerConfig
    private let session: URLSession

    var isAvailable: Bool {
        config.apiEndpoint != nil && config.apiKey != nil
    }

    init(config: SummarizerConfig) {
        self.config = config

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 60
        sessionConfig.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: sessionConfig)
    }

    func summarize(transcript: String, existingSummary: SummarizerOutput?) async throws -> SummarizerOutput {
        let prompt = SummarizerPrompts.ramblePrompt(transcript: transcript, existingSummary: existingSummary)
        return try await sendRequest(prompt: prompt)
    }

    func runGuidedThinking(
        transcript: String,
        previousQuestions: [String],
        previousAnswers: [String]
    ) async throws -> SummarizerOutput {
        let prompt = SummarizerPrompts.guidedPrompt(
            transcript: transcript,
            previousQuestions: previousQuestions,
            previousAnswers: previousAnswers
        )
        return try await sendRequest(prompt: prompt)
    }

    func analyzeDecision(transcript: String) async throws -> SummarizerOutput {
        let prompt = SummarizerPrompts.decisionPrompt(transcript: transcript)
        return try await sendRequest(prompt: prompt)
    }

    // MARK: - Private Methods

    private func sendRequest(prompt: String) async throws -> SummarizerOutput {
        guard let endpoint = config.apiEndpoint,
              let apiKey = config.apiKey,
              let url = URL(string: endpoint) else {
            throw SummarizerError.networkError("API not configured")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build request body (OpenAI-compatible format)
        let requestBody: [String: Any] = [
            "model": config.modelName ?? "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that analyzes voice transcripts and returns structured JSON responses."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Send request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizerError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummarizerError.networkError("API error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse response
        return try parseAPIResponse(data)
    }

    private func parseAPIResponse(_ data: Data) throws -> SummarizerOutput {
        // Parse OpenAI-compatible response format
        struct APIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let content = apiResponse.choices.first?.message.content else {
            throw SummarizerError.parsingFailed("No content in response")
        }

        // Parse the JSON content
        return try SummarizerOutput.parse(from: content)
    }
}

// MARK: - Anthropic API Support

/// Extension for Anthropic Claude API format
extension RemoteSummarizer {

    /// Create a summarizer configured for Anthropic's Claude API
    static func anthropic(apiKey: String, model: String = "claude-3-sonnet-20240229") -> RemoteSummarizer {
        let config = SummarizerConfig(
            apiEndpoint: "https://api.anthropic.com/v1/messages",
            apiKey: apiKey,
            modelName: model,
            maxTokens: 2048,
            temperature: 0.7
        )
        return RemoteSummarizer(config: config)
    }
}

// MARK: - OpenAI API Support

extension RemoteSummarizer {

    /// Create a summarizer configured for OpenAI's API
    static func openAI(apiKey: String, model: String = "gpt-4") -> RemoteSummarizer {
        let config = SummarizerConfig(
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: apiKey,
            modelName: model,
            maxTokens: 2048,
            temperature: 0.7
        )
        return RemoteSummarizer(config: config)
    }
}
