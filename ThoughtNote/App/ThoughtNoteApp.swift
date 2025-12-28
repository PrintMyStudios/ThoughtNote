import SwiftUI
import SwiftData
import AppIntents

/// Main entry point for ThoughtNote app
@main
struct ThoughtNoteApp: App {

    // MARK: - SwiftData Container

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Thought.self,
            TodoItem.self,
            ThoughtEntry.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - App State

    @State private var showingRecordSheet = false
    @State private var recordingMode: ThoughtMode = .ramble
    @State private var recordingSource: ThoughtSource = .manual
    @State private var appendToThought: Thought?

    var body: some Scene {
        WindowGroup {
            HomeView()
                .sheet(isPresented: $showingRecordSheet) {
                    // Pass the intent parameters to RecordView
                    RecordView(
                        initialMode: recordingMode,
                        source: recordingSource,
                        appendTo: appendToThought
                    )
                    .onDisappear {
                        // Reset state after sheet closes
                        recordingMode = .ramble
                        recordingSource = .manual
                        appendToThought = nil
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .startNewThought)) { notification in
                    handleStartNewThought(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .addToLatestThought)) { notification in
                    handleAddToLatestThought(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .addToThoughtByTitle)) { notification in
                    handleAddToThoughtByTitle(notification)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Intent Handlers

    private func handleStartNewThought(_ notification: Notification) {
        if let mode = notification.userInfo?["mode"] as? ThoughtMode {
            recordingMode = mode
        }
        if let source = notification.userInfo?["source"] as? ThoughtSource {
            recordingSource = source
        }
        appendToThought = nil
        showingRecordSheet = true
    }

    private func handleAddToLatestThought(_ notification: Notification) {
        // Find the latest thought
        let context = sharedModelContainer.mainContext
        var descriptor = FetchDescriptor<Thought>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let latestThought = try? context.fetch(descriptor).first {
            appendToThought = latestThought
            recordingMode = latestThought.mode
        }

        if let source = notification.userInfo?["source"] as? ThoughtSource {
            recordingSource = source
        }

        showingRecordSheet = true
    }

    private func handleAddToThoughtByTitle(_ notification: Notification) {
        guard let title = notification.userInfo?["title"] as? String else { return }

        // Search for thought by title
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Thought>(
            predicate: #Predicate { thought in
                thought.title.localizedStandardContains(title)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        if let matchingThought = try? context.fetch(descriptor).first {
            appendToThought = matchingThought
            recordingMode = matchingThought.mode
        }

        if let source = notification.userInfo?["source"] as? ThoughtSource {
            recordingSource = source
        }

        showingRecordSheet = true
    }
}

// MARK: - App Intent Dependencies

extension ModelContainer: @unchecked Sendable {}

struct ModelContainerKey: DependencyKey {
    static var defaultValue: ModelContainer {
        let schema = Schema([Thought.self, TodoItem.self, ThoughtEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}

extension DependencyValues {
    var modelContainer: ModelContainer {
        get { self[ModelContainerKey.self] }
        set { self[ModelContainerKey.self] = newValue }
    }
}
