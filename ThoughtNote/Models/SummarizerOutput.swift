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
    static func parse(from jsonString: String) throws -> SummarizerOutput {
        guard let data = jsonString.data(using: .utf8) else {
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
