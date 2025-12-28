import Foundation

/// The output structure from the summarizer, matching the required JSON contract
struct SummarizerOutput: Codable, Equatable {
    var title: String
    var summary: String
    var bullets: [String]
    var todos: [TodoItem.DTO]
    var questions: [String]?
    var decision: DecisionData?

    /// Default empty output
    static var empty: SummarizerOutput {
        SummarizerOutput(
            title: "",
            summary: "",
            bullets: [],
            todos: [],
            questions: nil,
            decision: nil
        )
    }
}

// MARK: - JSON Parsing

extension SummarizerOutput {
    /// Parse from JSON string with error handling
    /// Tolerant of markdown code fences and leading/trailing text
    static func parse(from jsonString: String) throws -> SummarizerOutput {
        // Clean the JSON string - remove markdown fences and extract JSON
        let cleanedJSON = extractJSON(from: jsonString)

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw SummarizerError.invalidJSON("Could not convert string to data")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(SummarizerOutput.self, from: data)
        } catch {
            throw SummarizerError.parsingFailed(error.localizedDescription)
        }
    }

    /// Extract JSON from a string that may contain markdown fences or surrounding text
    private static func extractJSON(from string: String) -> String {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code fences (```json ... ``` or ``` ... ```)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it still doesn't start with {, try to find the first { and last }
        if !cleaned.hasPrefix("{") {
            if let startIndex = cleaned.firstIndex(of: "{"),
               let endIndex = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[startIndex...endIndex])
            }
        }

        return cleaned
    }

    /// Convert to JSON string
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SummarizerError.invalidJSON("Could not convert data to string")
        }
        return string
    }
}

// MARK: - Summarizer Errors

enum SummarizerError: LocalizedError {
    case invalidJSON(String)
    case parsingFailed(String)
    case networkError(String)
    case modelError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .modelError(let message):
            return "Model error: \(message)"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}
