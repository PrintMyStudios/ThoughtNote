import Foundation

/// Gemini-based summarizer using Structured Outputs
/// Uses Gemini 2.5 Flash-Lite for fast, cost-effective summarization
final class GeminiSummarizer: Summarizer {

    let id = "gemini"
    let name = "Gemini Flash"

    private let apiKey: String
    private let modelName: String
    private let session: URLSession

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Constants

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private static let defaultModel = "gemini-2.0-flash-lite"

    // MARK: - Initialization

    init(apiKey: String, modelName: String = GeminiSummarizer.defaultModel) {
        self.apiKey = apiKey
        self.modelName = modelName

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Summarizer Protocol

    func summarize(transcript: String, existingSummary: SummarizerOutput?) async throws -> SummarizerOutput {
        let prompt = SummarizerPrompts.ramblePrompt(transcript: transcript, existingSummary: existingSummary)
        return try await sendRequest(prompt: prompt, schema: Self.rambleSchema)
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
        return try await sendRequest(prompt: prompt, schema: Self.guidedSchema)
    }

    func analyzeDecision(transcript: String) async throws -> SummarizerOutput {
        let prompt = SummarizerPrompts.decisionPrompt(transcript: transcript)
        return try await sendRequest(prompt: prompt, schema: Self.decisionSchema)
    }

    // MARK: - Private Methods

    private func sendRequest(prompt: String, schema: [String: Any]) async throws -> SummarizerOutput {
        guard !apiKey.isEmpty else {
            throw SummarizerError.networkError("Gemini API key is required")
        }

        let endpoint = "\(Self.baseURL)/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw SummarizerError.networkError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body with structured output
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        // Send request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizerError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw SummarizerError.networkError("API error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse response
        return try parseGeminiResponse(data)
    }

    private func parseGeminiResponse(_ data: Data) throws -> SummarizerOutput {
        // Parse the Gemini response structure
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw SummarizerError.parsingFailed("Invalid Gemini response structure")
        }

        // The text should be JSON due to structured output
        return try SummarizerOutput.parse(from: text)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }

    // MARK: - JSON Schemas for Structured Output

    /// Schema for ramble mode output
    private static let rambleSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": [
                "type": "string",
                "description": "A brief title (max 50 chars)"
            ],
            "summary": [
                "type": "string",
                "description": "A concise 1-3 sentence summary"
            ],
            "bullets": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Key points/ideas (3-7 items)"
            ],
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "dueDate": ["type": "string", "nullable": true],
                        "priority": ["type": "integer", "nullable": true]
                    ],
                    "required": ["text"]
                ],
                "description": "Action items mentioned"
            ]
        ],
        "required": ["title", "summary", "bullets", "todos"]
    ]

    /// Schema for guided mode output (includes questions)
    private static let guidedSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": [
                "type": "string",
                "description": "Updated title"
            ],
            "summary": [
                "type": "string",
                "description": "Updated summary incorporating new insights"
            ],
            "bullets": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Updated key points"
            ],
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "dueDate": ["type": "string", "nullable": true],
                        "priority": ["type": "integer", "nullable": true]
                    ],
                    "required": ["text"]
                ]
            ],
            "questions": [
                "type": "array",
                "items": ["type": "string"],
                "description": "1-2 thoughtful follow-up questions"
            ]
        ],
        "required": ["title", "summary", "bullets", "todos", "questions"]
    ]

    /// Schema for decision mode output
    private static let decisionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": [
                "type": "string",
                "description": "Brief description of the decision"
            ],
            "summary": [
                "type": "string",
                "description": "Summary of the decision context"
            ],
            "bullets": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Key factors to consider"
            ],
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "dueDate": ["type": "string", "nullable": true],
                        "priority": ["type": "integer", "nullable": true]
                    ],
                    "required": ["text"]
                ]
            ],
            "questions": [
                "type": "array",
                "items": ["type": "string"],
                "description": "What additional information would help?"
            ],
            "decision": [
                "type": "object",
                "properties": [
                    "recommendation": [
                        "type": "string",
                        "description": "Your recommendation with reasoning"
                    ],
                    "confidence": [
                        "type": "number",
                        "description": "0.0 to 1.0"
                    ],
                    "pros": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "text": ["type": "string"],
                                "weight": ["type": "integer", "description": "1-5"]
                            ],
                            "required": ["text", "weight"]
                        ]
                    ],
                    "cons": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "text": ["type": "string"],
                                "weight": ["type": "integer", "description": "1-5"]
                            ],
                            "required": ["text", "weight"]
                        ]
                    ],
                    "unknowns": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Things that could change the analysis"
                    ]
                ],
                "required": ["recommendation", "confidence", "pros", "cons", "unknowns"]
            ]
        ],
        "required": ["title", "summary", "bullets", "todos", "decision"]
    ]
}

// MARK: - Factory Extension

extension GeminiSummarizer {

    /// Create a Gemini summarizer from settings
    static func fromSettings() -> GeminiSummarizer? {
        guard let apiKey = KeychainHelper.getGeminiAPIKey(), !apiKey.isEmpty else {
            return nil
        }
        return GeminiSummarizer(apiKey: apiKey)
    }
}
