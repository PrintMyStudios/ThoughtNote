import SwiftUI

/// Settings view for configuring app behavior
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("summarizerType") private var summarizerType: SummarizerType = .stub
    @AppStorage("keepAudioFiles") private var keepAudioFiles = false
    @AppStorage("transcriptionLocale") private var transcriptionLocale = Locale.current.identifier
    @AppStorage("apiEndpoint") private var apiEndpoint = ""
    @AppStorage("showLiveTranscript") private var showLiveTranscript = true

    // API key is stored in Keychain, not AppStorage
    @State private var apiKey = ""
    @State private var showingAPIKeyAlert = false
    @State private var storageUsed: String = "Calculating..."
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?

    var body: some View {
        NavigationStack {
            Form {
                // Summarizer Section
                Section {
                    Picker("Summarizer", selection: $summarizerType) {
                        ForEach(SummarizerType.allCases) { type in
                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if summarizerType == .remote {
                        TextField("API Endpoint", text: $apiEndpoint)
                            .textContentType(.URL)
                            .autocapitalization(.none)

                        SecureField("API Key", text: $apiKey)
                            .onChange(of: apiKey) { oldValue, newValue in
                                // Save to Keychain when changed
                                if !newValue.isEmpty {
                                    KeychainHelper.saveAPIKey(newValue)
                                } else {
                                    KeychainHelper.deleteAPIKey()
                                }
                            }

                        if !apiKey.isEmpty {
                            Button {
                                testAPIConnection()
                            } label: {
                                if isTestingConnection {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingConnection)
                        }

                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("Success") ? .green : .red)
                        }
                    }
                } header: {
                    Text("Summarizer")
                } footer: {
                    switch summarizerType {
                    case .stub:
                        Text("Uses mock responses for testing. Great for development.")
                    case .remote:
                        Text("Connects to a cloud API for summarization. Requires API key.")
                    case .onDevice:
                        Text("Coming soon: Run summarization locally using llama.cpp.")
                    }
                }

                // Transcription Section
                Section {
                    Picker("Language", selection: $transcriptionLocale) {
                        ForEach(SpeechTranscriptionService.supportedLocales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier)
                        }
                    }

                    Toggle("Show Live Transcript", isOn: $showLiveTranscript)
                } header: {
                    Text("Transcription")
                } footer: {
                    if SpeechTranscriptionService(locale: Locale(identifier: transcriptionLocale)).supportsOnDevice {
                        Text("On-device transcription is available for this language.")
                    } else {
                        Text("Transcription requires an internet connection.")
                    }
                }

                // Storage Section
                Section {
                    Toggle("Keep Audio Files", isOn: $keepAudioFiles)

                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(storageUsed)
                            .foregroundStyle(.secondary)
                    }

                    if keepAudioFiles {
                        Button("Clear Audio Files", role: .destructive) {
                            clearAudioFiles()
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    if keepAudioFiles {
                        Text("Audio files are saved locally and can be played back later.")
                    } else {
                        Text("Audio is discarded after transcription to save space.")
                    }
                }

                // Privacy Section
                Section {
                    NavigationLink {
                        PrivacyInfoView()
                    } label: {
                        Label("Privacy Information", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        PermissionsView()
                    } label: {
                        Label("Permissions", systemImage: "lock.shield")
                    }
                } header: {
                    Text("Privacy & Permissions")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/thoughtnote")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                calculateStorageUsage()
                // Load API key from Keychain
                apiKey = KeychainHelper.getAPIKey() ?? ""
            }
        }
    }

    // MARK: - Actions

    private func testAPIConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                let config = SummarizerConfig(
                    apiEndpoint: apiEndpoint.isEmpty ? nil : apiEndpoint,
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    modelName: nil,
                    maxTokens: 100,
                    temperature: 0.7
                )
                let summarizer = RemoteSummarizer(config: config)

                // Try a simple summarization
                _ = try await summarizer.summarize(transcript: "Test connection.", existingSummary: nil)

                await MainActor.run {
                    connectionTestResult = "✓ Success! Connection working."
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = "✗ Failed: \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }

    private func calculateStorageUsage() {
        Task {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings")

            var totalSize: Int64 = 0

            if let enumerator = FileManager.default.enumerator(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
            }

            await MainActor.run {
                storageUsed = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            }
        }
    }

    private func clearAudioFiles() {
        Task {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings")

            try? FileManager.default.removeItem(at: recordingsPath)

            await MainActor.run {
                calculateStorageUsage()
            }
        }
    }
}

// MARK: - Privacy Info View

struct PrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PrivacySection(
                    title: "Audio Recording",
                    icon: "mic.fill",
                    description: "ThoughtNote records audio only when you explicitly start a recording session. Recordings are processed locally for transcription when possible."
                )

                PrivacySection(
                    title: "Speech Recognition",
                    icon: "waveform",
                    description: "Your voice is transcribed to text using Apple's Speech Recognition framework. When available, transcription happens entirely on your device."
                )

                PrivacySection(
                    title: "Summarization",
                    icon: "brain",
                    description: "Depending on your settings, summaries are generated either locally (coming soon) or via a remote API. When using remote APIs, your transcript text is sent to the configured service."
                )

                PrivacySection(
                    title: "Data Storage",
                    icon: "internaldrive",
                    description: "All your thoughts are stored locally on your device. Audio files can optionally be kept or discarded after transcription."
                )

                PrivacySection(
                    title: "No Tracking",
                    icon: "eye.slash",
                    description: "ThoughtNote does not collect analytics, track your usage, or share any data with third parties. Your thoughts remain private."
                )
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySection: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Permissions View

struct PermissionsView: View {
    @State private var hasMicrophonePermission = AudioRecordingService.hasMicrophonePermission
    @State private var hasSpeechPermission = SpeechTranscriptionService.hasSpeechPermission

    var body: some View {
        List {
            PermissionRow(
                title: "Microphone",
                description: "Required for recording your voice",
                icon: "mic.fill",
                isGranted: hasMicrophonePermission
            ) {
                Task {
                    hasMicrophonePermission = await AudioRecordingService.requestMicrophonePermission()
                }
            }

            PermissionRow(
                title: "Speech Recognition",
                description: "Required for transcribing your voice to text",
                icon: "waveform",
                isGranted: hasSpeechPermission
            ) {
                Task {
                    hasSpeechPermission = await SpeechTranscriptionService.requestSpeechPermission()
                }
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Enable") {
                    onRequest()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Codable Conformance for AppStorage

extension SummarizerType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "stub": self = .stub
        case "remote": self = .remote
        case "onDevice": self = .onDevice
        default: return nil
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
