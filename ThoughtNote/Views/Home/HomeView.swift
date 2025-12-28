import SwiftUI
import SwiftData

/// Main home view showing list of thoughts
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thought.updatedAt, order: .reverse) private var thoughts: [Thought]

    @State private var searchText = ""
    @State private var selectedMode: ThoughtMode? = nil
    @State private var showingRecordSheet = false
    @State private var showingSettings = false

    var filteredThoughts: [Thought] {
        var result = thoughts

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { thought in
                thought.title.localizedCaseInsensitiveContains(searchText) ||
                thought.summary.localizedCaseInsensitiveContains(searchText) ||
                thought.rawTranscript.localizedCaseInsensitiveContains(searchText) ||
                thought.bullets.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Filter by mode
        if let mode = selectedMode {
            result = result.filter { $0.mode == mode }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if thoughts.isEmpty {
                    EmptyStateView(showingRecordSheet: $showingRecordSheet)
                } else {
                    thoughtsList
                }

                // Floating record button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        RecordButton(showingRecordSheet: $showingRecordSheet)
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("ThoughtNote")
            .searchable(text: $searchText, prompt: "Search thoughts...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            selectedMode = nil
                        } label: {
                            Label("All Thoughts", systemImage: selectedMode == nil ? "checkmark" : "")
                        }

                        ForEach(ThoughtMode.allCases, id: \.self) { mode in
                            Button {
                                selectedMode = mode
                            } label: {
                                Label(mode.displayName, systemImage: selectedMode == mode ? "checkmark" : mode.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingRecordSheet) {
                RecordView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var thoughtsList: some View {
        List {
            if !filteredThoughts.isEmpty {
                ForEach(filteredThoughts) { thought in
                    NavigationLink(destination: ThoughtDetailView(thought: thought)) {
                        ThoughtRowView(thought: thought)
                    }
                }
                .onDelete(perform: deleteThoughts)
            } else if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteThoughts(at offsets: IndexSet) {
        for index in offsets {
            let thought = filteredThoughts[index]
            modelContext.delete(thought)
        }
        try? modelContext.save()
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    @Binding var showingRecordSheet: Bool

    var body: some View {
        ContentUnavailableView {
            Label("No Thoughts Yet", systemImage: "brain.head.profile")
        } description: {
            Text("Start capturing your thoughts by tapping the record button below.")
        } actions: {
            Button {
                showingRecordSheet = true
            } label: {
                Text("Start Recording")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Thought Row View

struct ThoughtRowView: View {
    let thought: Thought

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: thought.mode.iconName)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(thought.title.isEmpty ? "Untitled Thought" : thought.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(thought.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !thought.summary.isEmpty {
                Text(thought.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if !thought.bullets.isEmpty {
                    Label("\(thought.bullets.count)", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !thought.todos.isEmpty {
                    let completedCount = thought.todos.filter { $0.isDone }.count
                    Label("\(completedCount)/\(thought.todos.count)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if thought.mode == .decision, thought.decision != nil {
                    Label("Decision", systemImage: "scale.3d")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Floating Record Button

struct RecordButton: View {
    @Binding var showingRecordSheet: Bool

    var body: some View {
        Button {
            showingRecordSheet = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.red)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("New Thought")
        .accessibilityHint("Start recording a new thought")
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Thought.self, TodoItem.self, configurations: config)

    // Add sample data
    let sample = Thought.sample
    container.mainContext.insert(sample)

    return HomeView()
        .modelContainer(container)
}
