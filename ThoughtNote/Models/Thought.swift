import Foundation
import SwiftData

/// Source of how the thought was created
enum ThoughtSource: String, Codable, CaseIterable {
    case manual = "manual"
    case siri = "siri"
    case widget = "widget"
    case shortcut = "shortcut"
}

/// Mode of thought capture
enum ThoughtMode: String, Codable, CaseIterable {
    case ramble = "ramble"
    case guided = "guided"
    case decision = "decision"

    var displayName: String {
        switch self {
        case .ramble: return "Ramble On"
        case .guided: return "Guided Thinking"
        case .decision: return "Decision Helper"
        }
    }

    var description: String {
        switch self {
        case .ramble: return "Continuous capture until stop"
        case .guided: return "App asks clarifying questions"
        case .decision: return "Weigh pros/cons for decisions"
        }
    }

    var iconName: String {
        switch self {
        case .ramble: return "waveform"
        case .guided: return "questionmark.bubble"
        case .decision: return "scale.3d"
        }
    }
}

/// Main entity representing a captured thought/recording session
@Model
final class Thought {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var rawTranscript: String
    var summary: String

    /// Stored as JSON string for SwiftData compatibility
    var bulletsJSON: String

    /// Related to-do items
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.thought)
    var todos: [TodoItem]

    /// Tags stored as JSON string
    var tagsJSON: String

    var source: ThoughtSource
    var mode: ThoughtMode

    /// Whether this was recorded while driving (optional metadata)
    var isDriving: Bool

    /// Optional audio file path for keeping recordings
    var audioFilePath: String?

    /// Questions generated during guided mode (JSON string)
    var questionsJSON: String?

    /// Decision data for decision mode (JSON string)
    var decisionJSON: String?

    // MARK: - Computed Properties

    var bullets: [String] {
        get {
            guard let data = bulletsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                bulletsJSON = "[]"
                return
            }
            bulletsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    var tags: [String] {
        get {
            guard let data = tagsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                tagsJSON = "[]"
                return
            }
            tagsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    var questions: [String]? {
        get {
            guard let json = questionsJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            guard let value = newValue,
                  let data = try? JSONEncoder().encode(value) else {
                questionsJSON = nil
                return
            }
            questionsJSON = String(data: data, encoding: .utf8)
        }
    }

    var decision: DecisionData? {
        get {
            guard let json = decisionJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(DecisionData.self, from: data)
        }
        set {
            guard let value = newValue,
                  let data = try? JSONEncoder().encode(value) else {
                decisionJSON = nil
                return
            }
            decisionJSON = String(data: data, encoding: .utf8)
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "",
        rawTranscript: String = "",
        summary: String = "",
        bullets: [String] = [],
        todos: [TodoItem] = [],
        tags: [String] = [],
        source: ThoughtSource = .manual,
        mode: ThoughtMode = .ramble,
        isDriving: Bool = false,
        audioFilePath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.rawTranscript = rawTranscript
        self.summary = summary
        self.bulletsJSON = "[]"
        self.todos = todos
        self.tagsJSON = "[]"
        self.source = source
        self.mode = mode
        self.isDriving = isDriving
        self.audioFilePath = audioFilePath

        // Set computed properties after init
        self.bullets = bullets
        self.tags = tags
    }

    // MARK: - Methods

    /// Append transcript from a new recording session
    func appendTranscript(_ newTranscript: String) {
        if rawTranscript.isEmpty {
            rawTranscript = newTranscript
        } else {
            rawTranscript += "\n\n---\n\n" + newTranscript
        }
        updatedAt = Date()
    }

    /// Update from summarizer output
    func updateFromSummary(_ output: SummarizerOutput) {
        if !output.title.isEmpty {
            title = output.title
        }
        summary = output.summary
        bullets = output.bullets

        // Create TodoItem objects from output
        let newTodos = output.todos.map { TodoItem(from: $0) }
        todos.append(contentsOf: newTodos)

        if let questions = output.questions, !questions.isEmpty {
            self.questions = questions
        }

        if let decision = output.decision {
            self.decision = decision
        }

        updatedAt = Date()
    }
}

// MARK: - Decision Data Structure

struct DecisionData: Codable, Equatable {
    var recommendation: String
    var confidence: Double
    var pros: [WeightedItem]
    var cons: [WeightedItem]
    var unknowns: [String]

    struct WeightedItem: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var text: String
        var weight: Int

        enum CodingKeys: String, CodingKey {
            case text, weight
        }
    }
}

// MARK: - Sample Data for Previews

extension Thought {
    static var sample: Thought {
        let thought = Thought(
            title: "Product Launch Ideas",
            rawTranscript: "So I've been thinking about the product launch and I think we should focus on three main areas. First, we need to nail the messaging - it should be simple and clear. Second, we should partner with influencers who actually use products like ours. Third, we need a solid launch day plan with live demos. Oh, and I need to remember to call Sarah about the press release and schedule that meeting with the design team.",
            summary: "Planning the product launch with focus on clear messaging, influencer partnerships, and live demo strategy.",
            bullets: [
                "Focus on simple, clear messaging",
                "Partner with authentic influencers",
                "Plan live demos for launch day"
            ],
            source: .manual,
            mode: .ramble
        )

        thought.todos = [
            TodoItem(text: "Call Sarah about press release", priority: 1),
            TodoItem(text: "Schedule meeting with design team", priority: 2)
        ]

        return thought
    }

    static var decisionSample: Thought {
        let thought = Thought(
            title: "Should I take the new job offer?",
            rawTranscript: "I got a job offer from TechCorp. The salary is 20% higher but it's in a different city. My current job has great work-life balance but limited growth. The new role would be more challenging and I'd learn new technologies.",
            summary: "Weighing a job offer with higher salary and growth potential against current work-life balance.",
            mode: .decision
        )

        thought.decision = DecisionData(
            recommendation: "Consider taking the new job if career growth is your priority",
            confidence: 0.7,
            pros: [
                .init(text: "20% salary increase", weight: 3),
                .init(text: "More challenging role", weight: 2),
                .init(text: "Learn new technologies", weight: 2)
            ],
            cons: [
                .init(text: "Requires relocation", weight: 3),
                .init(text: "Lose current work-life balance", weight: 2)
            ],
            unknowns: [
                "Remote work policy at new company",
                "Team culture at TechCorp"
            ]
        )

        return thought
    }
}
