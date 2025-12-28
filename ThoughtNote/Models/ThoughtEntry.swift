import Foundation
import SwiftData

/// Represents a single transcript segment/entry within a Thought
/// Each entry captures a finalized segment of speech with its timestamp
@Model
final class ThoughtEntry {
    var id: UUID
    var createdAt: Date
    var transcript: String
    var summarySnippet: String?

    /// Parent thought relationship
    var thought: Thought?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcript: String,
        summarySnippet: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.summarySnippet = summarySnippet
    }
}

// MARK: - Convenience

extension ThoughtEntry {

    /// Duration since previous entry (for display purposes)
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - Sample Data

extension ThoughtEntry {

    static var sample: ThoughtEntry {
        ThoughtEntry(
            transcript: "So I've been thinking about the product launch and I think we should focus on three main areas.",
            summarySnippet: "Product launch focus areas"
        )
    }

    static var samples: [ThoughtEntry] {
        [
            ThoughtEntry(
                createdAt: Date().addingTimeInterval(-120),
                transcript: "So I've been thinking about the product launch and I think we should focus on three main areas."
            ),
            ThoughtEntry(
                createdAt: Date().addingTimeInterval(-90),
                transcript: "First, we need to nail the messaging - it should be simple and clear."
            ),
            ThoughtEntry(
                createdAt: Date().addingTimeInterval(-60),
                transcript: "Second, we should partner with influencers who actually use products like ours."
            ),
            ThoughtEntry(
                createdAt: Date().addingTimeInterval(-30),
                transcript: "Third, we need a solid launch day plan with live demos."
            )
        ]
    }
}
