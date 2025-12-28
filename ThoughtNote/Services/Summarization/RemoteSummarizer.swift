import Foundation

/// API provider type
enum APIProvider: String, Codable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case custom = "custom"  // OpenAI-compatible custom endpoint
}

/// Remote API-based summarizer
/// Configurable to work with various LLM API providers
final class RemoteSummarizer: Summarizer {

    let id = "remote"
    let name = "Remote API"

    private let config: SummarizerConfig
    private let provider: APIProvider
    private let session: URLSession

    var isAvailable: Bool {
        config.apiEndpoint != nil && config.apiKey != nil
    }

    init(config: SummarizerConfig, provider: APIProvider = .openAI) {
        self.config = config
        self.provider = provider

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

        // Set headers and build body based on provider
        switch provider {
        case .anthropic:
            request = buildAnthropicRequest(request, apiKey: apiKey, prompt: prompt)
        case .openAI, .custom:
            request = buildOpenAIRequest(request, apiKey: apiKey, prompt: prompt)
        }

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

        // Parse response based on provider
        return try parseAPIResponse(data, provider: provider)
    }

    private func buildOpenAIRequest(_ request: URLRequest, apiKey: String, prompt: String) -> URLRequest {
        var req = request
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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

        req.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        return req
    }

    private func buildAnthropicRequest(_ request: URLRequest, apiKey: String, prompt: String) -> URLRequest {
        var req = request
        // Anthropic uses different header names
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let requestBody: [String: Any] = [
            "model": config.modelName ?? "claude-3-sonnet-20240229",
            "max_tokens": config.maxTokens,
            "system": "You are a helpful assistant that analyzes voice transcripts and returns structured JSON responses. Always respond with valid JSON only.",
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        return req
    }

    private func parseAPIResponse(_ data: Data, provider: APIProvider) throws -> SummarizerOutput {
        let content: String

        switch provider {
        case .anthropic:
            content = try parseAnthropicResponse(data)
        case .openAI, .custom:
            content = try parseOpenAIResponse(data)
        }

        // Parse the JSON content
        return try SummarizerOutput.parse(from: content)
    }

    private func parseOpenAIResponse(_ data: Data) throws -> String {
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

        return content
    }

    private func parseAnthropicResponse(_ data: Data) throws -> String {
        struct AnthropicResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        // Find the text content block
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw SummarizerError.parsingFailed("No text content in Anthropic response")
        }

        return text
    }
}

// MARK: - Anthropic API Support

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
        return RemoteSummarizer(config: config, provider: .anthropic)
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
        return RemoteSummarizer(config: config, provider: .openAI)
    }

    /// Create a summarizer for a custom OpenAI-compatible endpoint
    static func custom(endpoint: String, apiKey: String, model: String) -> RemoteSummarizer {
        let config = SummarizerConfig(
            apiEndpoint: endpoint,
            apiKey: apiKey,
            modelName: model,
            maxTokens: 2048,
            temperature: 0.7
        )
        return RemoteSummarizer(config: config, provider: .custom)
    }
}
