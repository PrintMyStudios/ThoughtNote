import SwiftUI

/// Settings view for configuring app behavior
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // STT Settings
    @AppStorage("sttProvider") private var sttProvider: STTProviderType = .appleSpeech
    @AppStorage("transcriptionLocale") private var transcriptionLocale = Locale.current.identifier
    @AppStorage("showLiveTranscript") private var showLiveTranscript = true

    // Summarizer Settings
    @AppStorage("summarizerType") private var summarizerType: SummarizerType = .stub
    @AppStorage("apiEndpoint") private var apiEndpoint = ""

    // Storage Settings
    @AppStorage("keepAudioFiles") private var keepAudioFiles = false

    // API keys stored in Keychain
    @State private var sttAPIKey = ""
    @State private var geminiAPIKey = ""
    @State private var remoteAPIKey = ""

    // UI State
    @State private var storageUsed: String = "Calculating..."
    @State private var isTestingSTTConnection = false
    @State private var sttConnectionResult: String?
    @State private var isTestingSummarizerConnection = false
    @State private var summarizerConnectionResult: String?

    var body: some View {
        NavigationStack {
            Form {
                // STT Provider Section
                Section {
                    Picker("Provider", selection: $sttProvider) {
                        ForEach(STTProviderType.allCases) { provider in
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if sttProvider == .assemblyAI {
                        SecureField("AssemblyAI API Key", text: $sttAPIKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .onChange(of: sttAPIKey) { _, newValue in
                                if !newValue.isEmpty {
                                    KeychainHelper.saveSTTAPIKey(newValue)
                                } else {
                                    KeychainHelper.deleteSTTAPIKey()
                                }
                            }

                        if !sttAPIKey.isEmpty {
                            Button {
                                testSTTConnection()
                            } label: {
                                if isTestingSTTConnection {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingSTTConnection)
                        }

                        if let result = sttConnectionResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("Success") ? .green : .red)
                        }
                    }

                    Picker("Language", selection: $transcriptionLocale) {
                        ForEach(SpeechTranscriptionService.supportedLocales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier)
                        }
                    }

                    Toggle("Show Live Transcript", isOn: $showLiveTranscript)
                } header: {
                    Text("Speech-to-Text")
                } footer: {
                    switch sttProvider {
                    case .appleSpeech:
                        if SpeechTranscriptionService(locale: Locale(identifier: transcriptionLocale)).supportsOnDevice {
                            Text("On-device transcription is available for this language.")
                        } else {
                            Text("Transcription may require an internet connection.")
                        }
                    case .assemblyAI:
                        Text("Cloud-based streaming transcription. Requires internet connection.")
                    }
                }

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

                    if summarizerType == .gemini {
                        SecureField("Gemini API Key", text: $geminiAPIKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .onChange(of: geminiAPIKey) { _, newValue in
                                if !newValue.isEmpty {
                                    KeychainHelper.saveGeminiAPIKey(newValue)
                                } else {
                                    KeychainHelper.deleteGeminiAPIKey()
                                }
                            }

                        if !geminiAPIKey.isEmpty {
                            Button {
                                testSummarizerConnection()
                            } label: {
                                if isTestingSummarizerConnection {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingSummarizerConnection)
                        }

                        if let result = summarizerConnectionResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("Success") ? .green : .red)
                        }
                    }

                    if summarizerType == .remote {
                        TextField("API Endpoint", text: $apiEndpoint)
                            .textContentType(.URL)
                            .autocapitalization(.none)

                        SecureField("API Key", text: $remoteAPIKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .onChange(of: remoteAPIKey) { _, newValue in
                                if !newValue.isEmpty {
                                    KeychainHelper.saveAPIKey(newValue)
                                } else {
                                    KeychainHelper.deleteAPIKey()
                                }
                            }

                        if !remoteAPIKey.isEmpty {
                            Button {
                                testSummarizerConnection()
                            } label: {
                                if isTestingSummarizerConnection {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingSummarizerConnection)
                        }

                        if let result = summarizerConnectionResult {
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
                    case .gemini:
                        Text("Uses Google Gemini 2.5 Flash-Lite for fast, cost-effective summarization.")
                    case .remote:
                        Text("Connects to OpenAI or Anthropic API for summarization.")
                    case .onDevice:
                        Text("Coming soon: Run summarization locally using llama.cpp.")
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
                // Load API keys from Keychain
                sttAPIKey = KeychainHelper.getSTTAPIKey() ?? ""
                geminiAPIKey = KeychainHelper.getGeminiAPIKey() ?? ""
                remoteAPIKey = KeychainHelper.getAPIKey() ?? ""
            }
        }
    }

    // MARK: - Actions

    private func testSTTConnection() {
        isTestingSTTConnection = true
        sttConnectionResult = nil

        Task {
            do {
                // For AssemblyAI, we can test by checking if the API key is valid
                // by making a simple API call
                let url = URL(string: "https://api.assemblyai.com/v2/transcript")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(sttAPIKey, forHTTPHeaderField: "Authorization")

                let (_, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse

                await MainActor.run {
                    if httpResponse?.statusCode == 401 {
                        sttConnectionResult = "✗ Failed: Invalid API key"
                    } else {
                        sttConnectionResult = "✓ Success! API key is valid."
                    }
                    isTestingSTTConnection = false
                }
            } catch {
                await MainActor.run {
                    sttConnectionResult = "✗ Failed: \(error.localizedDescription)"
                    isTestingSTTConnection = false
                }
            }
        }
    }

    private func testSummarizerConnection() {
        isTestingSummarizerConnection = true
        summarizerConnectionResult = nil

        Task {
            do {
                let summarizer: Summarizer
                switch summarizerType {
                case .gemini:
                    summarizer = GeminiSummarizer(apiKey: geminiAPIKey)
                case .remote:
                    let config = SummarizerConfig(
                        apiEndpoint: apiEndpoint.isEmpty ? nil : apiEndpoint,
                        apiKey: remoteAPIKey.isEmpty ? nil : remoteAPIKey,
                        modelName: nil,
                        maxTokens: 100,
                        temperature: 0.7
                    )
                    summarizer = RemoteSummarizer(config: config)
                default:
                    await MainActor.run {
                        summarizerConnectionResult = "✓ No connection needed for this provider."
                        isTestingSummarizerConnection = false
                    }
                    return
                }

                // Try a simple summarization
                _ = try await summarizer.summarize(transcript: "Test connection.", existingSummary: nil)

                await MainActor.run {
                    summarizerConnectionResult = "✓ Success! Connection working."
                    isTestingSummarizerConnection = false
                }
            } catch {
                await MainActor.run {
                    summarizerConnectionResult = "✗ Failed: \(error.localizedDescription)"
                    isTestingSummarizerConnection = false
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
        case "gemini": self = .gemini
        case "remote": self = .remote
        case "onDevice": self = .onDevice
        default: return nil
        }
    }
}

extension STTProviderType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "appleSpeech": self = .appleSpeech
        case "assemblyAI": self = .assemblyAI
        default: return nil
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
