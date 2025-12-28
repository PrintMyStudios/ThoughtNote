import SwiftUI
import SwiftData

/// Recording view with driving-friendly large UI
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var audioService = AudioRecordingService()
    @StateObject private var transcriptionService = SpeechTranscriptionService()

    @State private var selectedMode: ThoughtMode = .ramble
    @State private var showingTranscript = false
    @State private var isProcessing = false
    @State private var error: Error?
    @State private var showingError = false
    @State private var appendToThought: Thought?
    @State private var keepAudioFile = false

    // Existing thoughts for "add to" functionality
    @Query(sort: \Thought.updatedAt, order: .reverse, animation: .default)
    private var recentThoughts: [Thought]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Mode selector (only before recording)
                if !audioService.isRecording && !isProcessing {
                    modePicker
                }

                Spacer()

                // Central recording area
                if audioService.isRecording {
                    recordingIndicator
                } else if isProcessing {
                    processingIndicator
                } else {
                    readyToRecordView
                }

                Spacer()

                // Live transcript toggle (only while recording)
                if audioService.isRecording {
                    transcriptToggle
                }

                // Main action button
                mainButton

                // Add to existing thought option
                if !audioService.isRecording && !isProcessing && !recentThoughts.isEmpty {
                    appendToThoughtPicker
                }
            }
            .padding()
            .navigationTitle("New Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task {
                            await cancelRecording()
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(error?.localizedDescription ?? "An unknown error occurred")
            }
            .task {
                await checkPermissions()
            }
        }
    }

    // MARK: - Components

    private var modePicker: some View {
        VStack(spacing: 12) {
            Text("Recording Mode")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $selectedMode) {
                ForEach(ThoughtMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var recordingIndicator: some View {
        VStack(spacing: 24) {
            // Pulsing waveform visualization
            WaveformView(level: audioService.audioLevel)
                .frame(height: 120)

            // Elapsed time - large for driving
            Text(audioService.formattedElapsedTime)
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            // Mode indicator
            Label(selectedMode.displayName, systemImage: selectedMode.iconName)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var processingIndicator: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.accentColor)

            Text("Processing...")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Transcribing and summarizing your thought")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var readyToRecordView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Tap to start recording")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(selectedMode.description)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var transcriptToggle: some View {
        VStack(spacing: 8) {
            Toggle("Show Live Transcript", isOn: $showingTranscript)
                .toggleStyle(.button)

            if showingTranscript && !transcriptionService.transcript.isEmpty {
                ScrollView {
                    Text(transcriptionService.transcript)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    private var mainButton: some View {
        Button {
            Task {
                if audioService.isRecording {
                    await stopRecording()
                } else {
                    await startRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(audioService.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                if audioService.isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isProcessing)
        .accessibilityLabel(audioService.isRecording ? "Stop Recording" : "Start Recording")
    }

    private var appendToThoughtPicker: some View {
        VStack(spacing: 8) {
            Text("Or add to existing thought:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("New Thought") {
                    appendToThought = nil
                }

                Divider()

                ForEach(recentThoughts.prefix(5)) { thought in
                    Button(thought.title.isEmpty ? "Untitled" : thought.title) {
                        appendToThought = thought
                    }
                }
            } label: {
                HStack {
                    Text(appendToThought?.title ?? "New Thought")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Actions

    private func checkPermissions() async {
        // Check microphone permission
        if !AudioRecordingService.hasMicrophonePermission {
            let granted = await AudioRecordingService.requestMicrophonePermission()
            if !granted {
                error = AudioRecordingError.permissionDenied
                showingError = true
                return
            }
        }

        // Check speech recognition permission
        if !SpeechTranscriptionService.hasSpeechPermission {
            let granted = await SpeechTranscriptionService.requestSpeechPermission()
            if !granted {
                error = SpeechTranscriptionError.permissionDenied
                showingError = true
            }
        }
    }

    private func startRecording() async {
        do {
            // Connect audio buffer to transcription
            audioService.onAudioBuffer = { [weak transcriptionService] buffer, time in
                transcriptionService?.processAudioBuffer(buffer, time: time)
            }

            // Start transcription first
            try transcriptionService.startTranscription()

            // Start audio recording
            try await audioService.startRecording(saveToFile: keepAudioFile)

        } catch {
            self.error = error
            showingError = true
        }
    }

    private func stopRecording() async {
        isProcessing = true

        // Stop recording
        let audioPath = await audioService.stopRecording()

        // Stop transcription and get final text
        let transcript = await transcriptionService.stopTranscription()

        // Process and save
        await processAndSave(transcript: transcript, audioPath: audioPath)

        isProcessing = false
        dismiss()
    }

    private func cancelRecording() async {
        if audioService.isRecording {
            _ = await audioService.stopRecording()
            _ = await transcriptionService.stopTranscription()
        }
        dismiss()
    }

    private func processAndSave(transcript: String, audioPath: URL?) async {
        guard !transcript.isEmpty else { return }

        // Get summarizer
        let summarizer = SummarizerFactory.create(type: .stub) // TODO: Use settings

        do {
            let existingSummary = appendToThought.map { thought -> SummarizerOutput in
                SummarizerOutput(
                    title: thought.title,
                    summary: thought.summary,
                    bullets: thought.bullets,
                    todos: thought.todos.map { TodoItem.DTO(text: $0.text, dueDate: $0.dueDate, priority: $0.priority) },
                    questions: thought.questions,
                    decision: thought.decision
                )
            }

            // Run appropriate summarization based on mode
            let output: SummarizerOutput
            switch selectedMode {
            case .ramble:
                output = try await summarizer.summarize(transcript: transcript, existingSummary: existingSummary)
            case .guided:
                output = try await summarizer.runGuidedThinking(
                    transcript: transcript,
                    previousQuestions: appendToThought?.questions ?? [],
                    previousAnswers: []
                )
            case .decision:
                output = try await summarizer.analyzeDecision(transcript: transcript)
            }

            // Update or create thought
            if let thought = appendToThought {
                thought.appendTranscript(transcript)
                thought.updateFromSummary(output)
                thought.audioFilePath = audioPath?.path
            } else {
                let thought = Thought(
                    rawTranscript: transcript,
                    source: .manual,
                    mode: selectedMode,
                    audioFilePath: audioPath?.path
                )
                thought.updateFromSummary(output)
                modelContext.insert(thought)
            }

            try modelContext.save()

        } catch {
            self.error = error
            showingError = true
        }
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    let level: Float
    let barCount = 20

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(level: barLevel(for: index))
            }
        }
    }

    private func barLevel(for index: Int) -> Float {
        // Create a wave pattern based on the audio level
        let center = Float(barCount) / 2
        let distance = abs(Float(index) - center) / center
        let baseLevel = max(0.1, level * (1 - distance * 0.5))
        // Add some randomness for visual interest
        let randomFactor = Float.random(in: 0.8...1.2)
        return min(1.0, baseLevel * randomFactor)
    }
}

struct WaveformBar: View {
    let level: Float

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 4, height: CGFloat(max(8, level * 100)))
            .animation(.easeInOut(duration: 0.1), value: level)
    }
}

// MARK: - Preview

#Preview {
    RecordView()
        .modelContainer(for: [Thought.self, TodoItem.self], inMemory: true)
}
