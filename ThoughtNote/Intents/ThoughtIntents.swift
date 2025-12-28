import AppIntents
import SwiftData
import SwiftUI

// MARK: - App Shortcuts Provider

struct ThoughtNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewThoughtIntent(),
            phrases: [
                "New thought in \(.applicationName)",
                "Start a thought in \(.applicationName)",
                "Record a thought with \(.applicationName)",
                "Capture a thought in \(.applicationName)"
            ],
            shortTitle: "New Thought",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: AddToLatestThoughtIntent(),
            phrases: [
                "Add to my latest thought in \(.applicationName)",
                "Continue my thought in \(.applicationName)",
                "Append to thought in \(.applicationName)"
            ],
            shortTitle: "Add to Thought",
            systemImageName: "plus.bubble"
        )

        AppShortcut(
            intent: QuickDecisionIntent(),
            phrases: [
                "Help me decide in \(.applicationName)",
                "Decision helper in \(.applicationName)",
                "Weigh options in \(.applicationName)"
            ],
            shortTitle: "Decision Helper",
            systemImageName: "scale.3d"
        )
    }
}

// MARK: - New Thought Intent

struct NewThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "New Thought"
    static var description = IntentDescription("Start recording a new thought")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Mode")
    var mode: ThoughtModeEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a new \(\.$mode) thought")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Signal to the app to open recording view
        NotificationCenter.default.post(
            name: .startNewThought,
            object: nil,
            userInfo: ["mode": mode?.mode ?? ThoughtMode.ramble, "source": ThoughtSource.siri]
        )

        return .result(dialog: "Starting your thought recording...")
    }
}

// MARK: - Add to Latest Thought Intent

struct AddToLatestThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Latest Thought"
    static var description = IntentDescription("Continue recording and add to your most recent thought")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Signal to the app to open recording view with append mode
        NotificationCenter.default.post(
            name: .addToLatestThought,
            object: nil,
            userInfo: ["source": ThoughtSource.siri]
        )

        return .result(dialog: "Adding to your latest thought...")
    }
}

// MARK: - Add to Specific Thought Intent

struct AddToThoughtByTitleIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Thought by Title"
    static var description = IntentDescription("Find a thought by title and add to it")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Thought Title")
    var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add to thought titled \(\.$title)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: .addToThoughtByTitle,
            object: nil,
            userInfo: ["title": title, "source": ThoughtSource.siri]
        )

        return .result(dialog: "Looking for '\(title)'...")
    }
}

// MARK: - Quick Decision Intent

struct QuickDecisionIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Decision"
    static var description = IntentDescription("Start the decision helper mode")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: .startNewThought,
            object: nil,
            userInfo: ["mode": ThoughtMode.decision, "source": ThoughtSource.siri]
        )

        return .result(dialog: "Starting decision helper. Tell me what you're deciding...")
    }
}

// MARK: - Guided Thinking Intent

struct GuidedThinkingIntent: AppIntent {
    static var title: LocalizedStringResource = "Guided Thinking"
    static var description = IntentDescription("Start a guided thinking session with follow-up questions")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: .startNewThought,
            object: nil,
            userInfo: ["mode": ThoughtMode.guided, "source": ThoughtSource.siri]
        )

        return .result(dialog: "Starting guided thinking. Share your initial thoughts...")
    }
}

// MARK: - List Thoughts Intent

struct ListThoughtsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Recent Thoughts"
    static var description = IntentDescription("Show your recent thoughts")

    @Parameter(title: "Count", default: 5)
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Show my last \(\.$count) thoughts")
    }

    @Dependency
    private var modelContainer: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ThoughtEntity]> & ProvidesDialog {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = count

        let thoughts = try context.fetch(descriptor)
        let entities = thoughts.map { ThoughtEntity(thought: $0) }

        if entities.isEmpty {
            return .result(
                value: entities,
                dialog: "You don't have any thoughts yet. Say 'New thought' to get started."
            )
        }

        let titles = entities.prefix(3).map { $0.title }.joined(separator: ", ")
        return .result(
            value: entities,
            dialog: "Your recent thoughts include: \(titles)"
        )
    }
}

// MARK: - Thought Mode Entity

struct ThoughtModeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Thought Mode"
    static var defaultQuery = ThoughtModeQuery()

    var id: String
    var mode: ThoughtMode

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: mode.displayName))
    }

    static var allModes: [ThoughtModeEntity] {
        ThoughtMode.allCases.map { ThoughtModeEntity(id: $0.rawValue, mode: $0) }
    }
}

struct ThoughtModeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ThoughtModeEntity] {
        ThoughtModeEntity.allModes.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ThoughtModeEntity] {
        ThoughtModeEntity.allModes
    }
}

// MARK: - Thought Entity

struct ThoughtEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Thought"
    static var defaultQuery = ThoughtEntityQuery()

    var id: String
    var title: String
    var summary: String
    var mode: ThoughtMode
    var createdAt: Date

    init(thought: Thought) {
        self.id = thought.id.uuidString
        self.title = thought.title.isEmpty ? "Untitled" : thought.title
        self.summary = thought.summary
        self.mode = thought.mode
        self.createdAt = thought.createdAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: summary.prefix(50) + (summary.count > 50 ? "..." : ""))
        )
    }
}

struct ThoughtEntityQuery: EntityQuery {
    @Dependency
    private var modelContainer: ModelContainer

    func entities(for identifiers: [String]) async throws -> [ThoughtEntity] {
        let context = await modelContainer.mainContext
        let uuids = identifiers.compactMap { UUID(uuidString: $0) }

        var thoughts: [Thought] = []
        for uuid in uuids {
            var descriptor = FetchDescriptor<Thought>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            if let thought = try await context.fetch(descriptor).first {
                thoughts.append(thought)
            }
        }

        return thoughts.map { ThoughtEntity(thought: $0) }
    }

    func suggestedEntities() async throws -> [ThoughtEntity] {
        let context = await modelContainer.mainContext
        var descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10

        let thoughts = try await context.fetch(descriptor)
        return thoughts.map { ThoughtEntity(thought: $0) }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startNewThought = Notification.Name("startNewThought")
    static let addToLatestThought = Notification.Name("addToLatestThought")
    static let addToThoughtByTitle = Notification.Name("addToThoughtByTitle")
}
