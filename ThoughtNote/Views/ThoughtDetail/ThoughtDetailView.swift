import SwiftUI
import SwiftData

/// Detailed view of a thought showing summary, bullets, todos, and transcript
struct ThoughtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var thought: Thought

    @State private var showingTranscript = false
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with mode and date
                headerSection

                // Summary section
                if !thought.summary.isEmpty {
                    summarySection
                }

                // Decision section (if decision mode)
                if thought.mode == .decision, let decision = thought.decision {
                    decisionSection(decision)
                }

                // Bullets section
                if !thought.bullets.isEmpty {
                    bulletsSection
                }

                // Todos section
                if !thought.todos.isEmpty {
                    todosSection
                }

                // Guided questions (if guided mode)
                if thought.mode == .guided, let questions = thought.questions, !questions.isEmpty {
                    questionsSection(questions)
                }

                // Entries section (if available)
                if !thought.entries.isEmpty {
                    entriesSection
                }

                // Transcript section (fallback for raw transcript)
                transcriptSection
            }
            .padding()
        }
        .navigationTitle(thought.title.isEmpty ? "Thought" : thought.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Title", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [thought.exportAsMarkdown()])
        }
        .alert("Edit Title", isPresented: $isEditing) {
            TextField("Title", text: $thought.title)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                try? modelContext.save()
            }
        }
        .alert("Delete Thought?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(thought)
                try? modelContext.save()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Label(thought.mode.displayName, systemImage: thought.mode.iconName)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(.accentColor)
                .cornerRadius(8)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(thought.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(thought.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Summary", icon: "text.alignleft")

            Text(thought.summary)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func decisionSection(_ decision: DecisionData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Decision Analysis", icon: "scale.3d")

            // Recommendation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recommendation")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    // Confidence indicator
                    ConfidenceIndicator(confidence: decision.confidence)
                }

                Text(decision.recommendation)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Pros
            VStack(alignment: .leading, spacing: 8) {
                Text("Pros")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                ForEach(decision.pros) { pro in
                    WeightedItemRow(item: pro, isPositive: true)
                }
            }

            // Cons
            VStack(alignment: .leading, spacing: 8) {
                Text("Cons")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)

                ForEach(decision.cons) { con in
                    WeightedItemRow(item: con, isPositive: false)
                }
            }

            // Unknowns
            if !decision.unknowns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unknowns")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    ForEach(decision.unknowns, id: \.self) { unknown in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.orange)
                            Text(unknown)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }

    private var bulletsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Key Points", icon: "list.bullet")

            ForEach(Array(thought.bullets.enumerated()), id: \.offset) { index, bullet in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(bullet)
                        .font(.body)
                }
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "To-Dos", icon: "checkmark.circle")

            ForEach(thought.todos) { todo in
                TodoRowView(todo: todo) {
                    try? modelContext.save()
                }
            }
        }
    }

    private func questionsSection(_ questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Follow-up Questions", icon: "questionmark.bubble")

            ForEach(questions, id: \.self) { question in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.accentColor)

                    Text(question)
                        .font(.body)
                }
            }
        }
    }

    @State private var showingEntries = false

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    showingEntries.toggle()
                }
            } label: {
                HStack {
                    SectionHeader(title: "Entries (\(thought.entries.count))", icon: "list.bullet.rectangle")
                    Spacer()
                    Image(systemName: showingEntries ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showingEntries {
                VStack(spacing: 12) {
                    ForEach(thought.entries.sorted { $0.createdAt < $1.createdAt }) { entry in
                        EntryRowView(entry: entry)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    showingTranscript.toggle()
                }
            } label: {
                HStack {
                    SectionHeader(title: "Transcript", icon: "waveform")
                    Spacer()
                    Image(systemName: showingTranscript ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showingTranscript {
                Text(thought.rawTranscript)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct TodoRowView: View {
    @Bindable var todo: TodoItem
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                todo.isDone.toggle()
                onToggle()
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? .green : .secondary)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.text)
                    .font(.body)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)

                HStack(spacing: 8) {
                    if let dueDate = todo.dueDate {
                        Label(dueDate, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let priority = todo.priority {
                        PriorityBadge(priority: priority)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text(priorityText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundStyle(priorityColor)
            .cornerRadius(4)
    }

    private var priorityText: String {
        switch priority {
        case 1: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        default: return .blue
        }
    }
}

struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)

            Text("confidence")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.2))
        .foregroundStyle(confidenceColor)
        .cornerRadius(4)
    }

    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

struct WeightedItemRow: View {
    let item: DecisionData.WeightedItem
    let isPositive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Weight indicator
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(index < item.weight ? (isPositive ? Color.green : Color.red) : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Text(item.text)
                .font(.body)
        }
    }
}

struct EntryRowView: View {
    let entry: ThoughtEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Timestamp
            Text(entry.createdAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Transcript text
            Text(entry.transcript)
                .font(.body)
                .foregroundStyle(.primary)

            // Summary snippet (if available)
            if let snippet = entry.summarySnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.accentColor)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Export Extension

extension Thought {
    func exportAsMarkdown() -> String {
        var md = "# \(title.isEmpty ? "Untitled Thought" : title)\n\n"
        md += "*\(createdAt.formatted(date: .long, time: .shortened))*\n\n"

        if !summary.isEmpty {
            md += "## Summary\n\n\(summary)\n\n"
        }

        if !bullets.isEmpty {
            md += "## Key Points\n\n"
            for bullet in bullets {
                md += "- \(bullet)\n"
            }
            md += "\n"
        }

        if !todos.isEmpty {
            md += "## To-Dos\n\n"
            for todo in todos {
                let checkbox = todo.isDone ? "[x]" : "[ ]"
                md += "- \(checkbox) \(todo.text)\n"
            }
            md += "\n"
        }

        if let decision = decision {
            md += "## Decision Analysis\n\n"
            md += "**Recommendation:** \(decision.recommendation)\n\n"
            md += "**Confidence:** \(Int(decision.confidence * 100))%\n\n"

            md += "### Pros\n"
            for pro in decision.pros {
                md += "- \(pro.text) (weight: \(pro.weight)/5)\n"
            }

            md += "\n### Cons\n"
            for con in decision.cons {
                md += "- \(con.text) (weight: \(con.weight)/5)\n"
            }

            if !decision.unknowns.isEmpty {
                md += "\n### Unknowns\n"
                for unknown in decision.unknowns {
                    md += "- \(unknown)\n"
                }
            }
            md += "\n"
        }

        md += "## Transcript\n\n\(rawTranscript)\n"

        return md
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThoughtDetailView(thought: Thought.sample)
    }
    .modelContainer(for: [Thought.self, TodoItem.self, ThoughtEntry.self], inMemory: true)
}

#Preview("Decision") {
    NavigationStack {
        ThoughtDetailView(thought: Thought.decisionSample)
    }
    .modelContainer(for: [Thought.self, TodoItem.self, ThoughtEntry.self], inMemory: true)
}
