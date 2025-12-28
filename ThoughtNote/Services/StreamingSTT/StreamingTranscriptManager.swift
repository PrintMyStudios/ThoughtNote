import Foundation
import AVFoundation
import Combine

/// Manager that provides a unified interface for streaming transcription
/// Supports switching between Apple Speech and AssemblyAI providers
@MainActor
final class StreamingTranscriptManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var finalTranscript: String = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var error: Error?

    /// Combined transcript (finalized + partial)
    var fullTranscript: String {
        if partialTranscript.isEmpty {
            return finalTranscript
        } else if finalTranscript.isEmpty {
            return partialTranscript
        } else {
            return finalTranscript + " " + partialTranscript
        }
    }

    // MARK: - Callbacks

    /// Called when a final transcript segment is received
    var onFinalSegment: ((String) -> Void)?

    // MARK: - Private Properties

    private var sttService: StreamingSpeechToTextService?
    private var appleSpeechService: SpeechTranscriptionService?
    private var cancellables = Set<AnyCancellable>()

    private let configuration: STTConfiguration
    private let sampleRate: Int = 16000
    private let channels: Int = 1

    // Thread-safe state for audio callbacks
    private let stateQueue = DispatchQueue(label: "com.thoughtnote.transcript.state")
    private var _isStreamingInternal = false

    // MARK: - Initialization

    init(configuration: STTConfiguration) {
        self.configuration = configuration
        super.init()
    }

    convenience override init() {
        self.init(configuration: .default)
    }

    // MARK: - Public Methods

    /// Start streaming transcription
    func startStreaming() async throws {
        guard !isStreaming else {
            throw StreamingSTTError.alreadyStreaming
        }

        // Reset state
        partialTranscript = ""
        finalTranscript = ""
        error = nil

        switch configuration.provider {
        case .appleSpeech:
            try await startAppleSpeech()

        case .assemblyAI:
            try await startAssemblyAI()
        }

        stateQueue.sync { _isStreamingInternal = true }
        isStreaming = true
    }

    /// Stop streaming transcription
    func stopStreaming() async -> String {
        guard isStreaming else { return fullTranscript }

        stateQueue.sync { _isStreamingInternal = false }

        switch configuration.provider {
        case .appleSpeech:
            if let service = appleSpeechService {
                _ = await service.stopTranscription()
            }
            appleSpeechService = nil

        case .assemblyAI:
            await sttService?.stop()
            sttService = nil
        }

        // Finalize any remaining partial transcript
        if !partialTranscript.isEmpty {
            if !finalTranscript.isEmpty {
                finalTranscript += " "
            }
            finalTranscript += partialTranscript
            partialTranscript = ""
        }

        isStreaming = false
        cancellables.removeAll()

        return finalTranscript
    }

    /// Process audio buffer from recording service
    /// Note: Called from audio thread, must be thread-safe
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        var shouldProcess = false
        stateQueue.sync { shouldProcess = _isStreamingInternal }
        guard shouldProcess else { return }

        switch configuration.provider {
        case .appleSpeech:
            appleSpeechService?.processAudioBuffer(buffer, time: time)

        case .assemblyAI:
            // Convert to 16-bit PCM and send
            if let pcmData = AssemblyAIStreamingService.convertToInt16PCM(buffer) {
                sttService?.sendAudio(pcmData)
            }
        }
    }

    // MARK: - Private Methods - Apple Speech

    private func startAppleSpeech() async throws {
        let service = SpeechTranscriptionService(locale: Locale(identifier: configuration.language))
        appleSpeechService = service

        // Subscribe to transcript updates
        service.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                self?.partialTranscript = transcript
            }
            .store(in: &cancellables)

        // Subscribe to segment finalization
        service.onSegmentFinalized = { [weak self] segment in
            Task { @MainActor in
                self?.handleFinalSegment(segment.text)
            }
        }

        try service.startTranscription()
    }

    // MARK: - Private Methods - AssemblyAI

    private func startAssemblyAI() async throws {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw StreamingSTTError.notConfigured("AssemblyAI API key is required")
        }

        let service = AssemblyAIStreamingService(apiKey: apiKey)
        service.delegate = self
        sttService = service

        try await service.start(sampleRate: sampleRate, channels: channels)
    }

    // MARK: - Segment Handling

    private func handleFinalSegment(_ text: String) {
        guard !text.isEmpty else { return }

        // Append to final transcript
        if !finalTranscript.isEmpty {
            finalTranscript += " "
        }
        finalTranscript += text

        // Clear partial since it's now finalized
        partialTranscript = ""

        // Notify callback
        onFinalSegment?(text)
    }
}

// MARK: - StreamingSTTDelegate

extension StreamingTranscriptManager: StreamingSTTDelegate {

    nonisolated func streamingSTT(_ service: StreamingSpeechToTextService, didReceivePartialTranscript text: String) {
        Task { @MainActor in
            self.partialTranscript = text
        }
    }

    nonisolated func streamingSTT(_ service: StreamingSpeechToTextService, didReceiveFinalTranscript text: String) {
        Task { @MainActor in
            self.handleFinalSegment(text)
        }
    }

    nonisolated func streamingSTT(_ service: StreamingSpeechToTextService, didEncounterError error: Error) {
        Task { @MainActor in
            self.error = error
        }
    }

    nonisolated func streamingSTTDidConnect(_ service: StreamingSpeechToTextService) {
        // Connection established
    }

    nonisolated func streamingSTTDidDisconnect(_ service: StreamingSpeechToTextService) {
        Task { @MainActor in
            if self.isStreaming {
                // Unexpected disconnect
                self.isStreaming = false
            }
        }
    }
}

// MARK: - Factory

extension StreamingTranscriptManager {

    /// Create a transcript manager based on current settings
    static func fromSettings() -> StreamingTranscriptManager {
        // Get provider from UserDefaults
        let providerRaw = UserDefaults.standard.string(forKey: "sttProvider") ?? STTProviderType.appleSpeech.rawValue
        let provider = STTProviderType(rawValue: providerRaw) ?? .appleSpeech

        // Get API key from Keychain
        let apiKey = KeychainHelper.getSTTAPIKey()

        // Get language from settings
        let language = UserDefaults.standard.string(forKey: "transcriptionLocale") ?? Locale.current.identifier

        let config = STTConfiguration(
            provider: provider,
            apiKey: apiKey,
            language: language
        )

        return StreamingTranscriptManager(configuration: config)
    }
}
