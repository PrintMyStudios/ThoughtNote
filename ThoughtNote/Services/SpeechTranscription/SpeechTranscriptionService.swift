import Foundation
import Speech
import AVFoundation
import Combine

/// Service for real-time and batch speech-to-text transcription
/// Note: This class is not @MainActor because processAudioBuffer is called from audio thread.
/// Published properties are updated on the main thread.
final class SpeechTranscriptionService: NSObject, ObservableObject {

    // MARK: - Published State (updated on main thread)

    @Published private(set) var transcript: String = ""
    @Published private(set) var isTranscribing = false
    @Published private(set) var error: SpeechTranscriptionError?
    @Published private(set) var confidence: Float = 0

    /// Segments with timestamps for chunking
    @Published private(set) var segments: [TranscriptSegment] = []

    // MARK: - Speech Recognition

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Thread-safe flag for transcription state
    private let stateQueue = DispatchQueue(label: "com.thoughtnote.transcription.state")
    private var _isTranscribingInternal = false

    // MARK: - Settings

    private let locale: Locale

    /// Callback when a segment is finalized
    var onSegmentFinalized: ((TranscriptSegment) -> Void)?

    // MARK: - Segment Tracking

    private var currentSegmentStart: Date?
    private var currentSegmentText: String = ""
    private var segmentTimer: Timer?
    private let segmentDuration: TimeInterval = 30 // Finalize segment every 30 seconds

    // MARK: - Initialization

    init(locale: Locale = .current) {
        self.locale = locale
        super.init()

        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.defaultTaskHint = .dictation
    }

    // MARK: - Public Methods

    /// Start streaming transcription
    @MainActor
    func startTranscription() throws {
        guard !isTranscribing else {
            throw SpeechTranscriptionError.alreadyTranscribing
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw SpeechTranscriptionError.requestCreationFailed
        }

        // Configure for streaming results
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        // Enable on-device recognition if available (iOS 13+)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        // Start segment timer
        currentSegmentStart = Date()
        currentSegmentText = ""
        startSegmentTimer()

        transcript = ""
        segments = []
        stateQueue.sync { _isTranscribingInternal = true }
        isTranscribing = true
        self.error = nil
    }

    /// Stop transcription
    @MainActor
    func stopTranscription() async -> String {
        guard isTranscribing else { return transcript }

        // Update thread-safe flag first
        stateQueue.sync { _isTranscribingInternal = false }

        // Finalize current segment
        finalizeCurrentSegment()

        // Stop segment timer
        stopSegmentTimer()

        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        isTranscribing = false

        return transcript
    }

    /// Process audio buffer from recording service
    /// Note: This is called from the audio render thread, so we use thread-safe state check
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Use thread-safe flag check
        var shouldProcess = false
        stateQueue.sync { shouldProcess = _isTranscribingInternal }
        guard shouldProcess else { return }
        recognitionRequest?.append(buffer)
    }

    /// Transcribe from audio file (batch processing)
    func transcribeFile(at url: URL) async throws -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: SpeechTranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check if it's a cancellation (expected) or actual error
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1 {
                // User cancelled - not an error
                return
            }

            self.error = .recognitionFailed(error.localizedDescription)
            return
        }

        guard let result = result else { return }

        // Update transcript
        let newTranscript = result.bestTranscription.formattedString
        transcript = newTranscript
        currentSegmentText = newTranscript

        // Update confidence
        if let lastSegment = result.bestTranscription.segments.last {
            confidence = lastSegment.confidence
        }

        // Check if result is final
        if result.isFinal {
            finalizeCurrentSegment()
        }
    }

    /// Start timer for segment finalization
    private func startSegmentTimer() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.finalizeCurrentSegment()
            }
        }
    }

    /// Stop segment timer
    private func stopSegmentTimer() {
        segmentTimer?.invalidate()
        segmentTimer = nil
    }

    /// Finalize the current segment
    private func finalizeCurrentSegment() {
        guard !currentSegmentText.isEmpty,
              let startTime = currentSegmentStart else { return }

        // Get the new text since last segment
        let previousText = segments.map { $0.text }.joined(separator: " ")
        var newText = currentSegmentText
        if newText.hasPrefix(previousText) {
            newText = String(newText.dropFirst(previousText.count)).trimmingCharacters(in: .whitespaces)
        }

        guard !newText.isEmpty else { return }

        let segment = TranscriptSegment(
            id: UUID(),
            text: newText,
            startTime: startTime,
            endTime: Date(),
            confidence: confidence
        )

        segments.append(segment)
        onSegmentFinalized?(segment)

        // Reset for next segment
        currentSegmentStart = Date()
    }
}

// MARK: - Transcript Segment

struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let startTime: Date
    let endTime: Date
    let confidence: Float

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Errors

enum SpeechTranscriptionError: LocalizedError {
    case alreadyTranscribing
    case recognizerUnavailable
    case requestCreationFailed
    case recognitionFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyTranscribing:
            return "Transcription is already in progress"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        case .permissionDenied:
            return "Speech recognition permission denied"
        }
    }
}

// MARK: - Permission Handling

extension SpeechTranscriptionService {

    /// Check if speech recognition permission is granted
    static var hasSpeechPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Request speech recognition permission
    static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Check if recognizer supports on-device recognition
    var supportsOnDevice: Bool {
        if #available(iOS 13, *) {
            return speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        return false
    }
}

// MARK: - Locale Support

extension SpeechTranscriptionService {

    /// Get list of supported locales
    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
    }

    /// Check if a locale is supported
    static func isLocaleSupported(_ locale: Locale) -> Bool {
        SFSpeechRecognizer.supportedLocales().contains(locale)
    }
}
