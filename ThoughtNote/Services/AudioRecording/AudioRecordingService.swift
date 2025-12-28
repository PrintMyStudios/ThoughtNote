import Foundation
import AVFoundation
import Combine

/// Audio recording service that handles capture, metering, and file management
/// Configured to work alongside other audio (navigation, music) without interruption
/// Note: This class is not @MainActor because audio taps run on the audio render thread.
/// Published properties are updated on the main thread via DispatchQueue.main.
final class AudioRecordingService: NSObject, ObservableObject {

    // MARK: - Published State (updated on main thread)

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0 // 0.0 to 1.0
    @Published private(set) var error: AudioRecordingError?

    // MARK: - Audio Engine Components

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var audioFilePath: URL?

    // MARK: - Thread-safe state
    private let audioFileQueue = DispatchQueue(label: "com.thoughtnote.audiofile")
    private var _audioFileRef: AVAudioFile?

    // MARK: - Timer

    private var timer: Timer?
    private var startTime: Date?
    private var accumulatedTime: TimeInterval = 0

    // MARK: - Audio Buffer for Transcription

    /// Callback for sending audio buffers to speech transcription
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    // MARK: - Settings

    private let sampleRate: Double = 16000 // Optimal for speech recognition
    private let channelCount: AVAudioChannelCount = 1 // Mono for speech

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Start recording audio
    /// - Parameters:
    ///   - saveToFile: Whether to save audio to file (for playback/storage)
    /// - Returns: The file path if saving, nil otherwise
    @discardableResult
    func startRecording(saveToFile: Bool = false) async throws -> URL? {
        guard !isRecording else {
            throw AudioRecordingError.alreadyRecording
        }

        // Configure audio session for mixing with other audio
        try configureAudioSession()

        // Set up audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioRecordingError.engineCreationFailed
        }

        inputNode = engine.inputNode
        guard let inputNode = inputNode else {
            throw AudioRecordingError.inputNodeUnavailable
        }

        // Get the native format and create our desired format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AudioRecordingError.formatCreationFailed
        }

        // Set up audio file if saving
        if saveToFile {
            audioFilePath = try createAudioFilePath()
            let file = try AVAudioFile(
                forWriting: audioFilePath!,
                settings: recordingFormat.settings
            )
            audioFileQueue.sync { _audioFileRef = file }
            audioFile = file
        }

        // Install tap on input node
        // Use a converter if sample rates differ
        let bufferSize: AVAudioFrameCount = 1024

        if inputFormat.sampleRate != sampleRate {
            // Need to convert
            guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
                throw AudioRecordingError.converterCreationFailed
            }

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
                self?.processBuffer(buffer, time: time, converter: converter, outputFormat: recordingFormat)
            }
        } else {
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, time in
                self?.processBuffer(buffer, time: time, converter: nil, outputFormat: recordingFormat)
            }
        }

        // Start engine
        engine.prepare()
        try engine.start()

        // Start timer and update state on main thread
        DispatchQueue.main.async {
            self.startTime = Date()
            self.accumulatedTime = 0
            self.startTimer()
            self.isRecording = true
            self.isPaused = false
            self.error = nil
        }

        return audioFilePath
    }

    /// Stop recording
    @MainActor
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        // Stop timer
        stopTimer()
        accumulatedTime = 0
        elapsedTime = 0

        // Stop audio engine
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        // Close audio file thread-safely
        audioFileQueue.sync { _audioFileRef = nil }
        audioFile = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        isPaused = false
        audioLevel = 0

        let filePath = audioFilePath
        audioFilePath = nil

        return filePath
    }

    /// Pause recording
    func pauseRecording() {
        guard isRecording, !isPaused else { return }

        audioEngine?.pause()
        accumulatedTime = elapsedTime
        stopTimer()
        isPaused = true
    }

    /// Resume recording
    func resumeRecording() throws {
        guard isRecording, isPaused else { return }

        try audioEngine?.start()
        startTime = Date()
        startTimer()
        isPaused = false
    }

    /// Delete the current audio file
    func deleteAudioFile(at path: URL) {
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - Private Methods

    /// Configure audio session for recording while allowing other audio
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Use playAndRecord with mixing options
        // This allows recording while other audio plays (maps, music)
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [
                .mixWithOthers,           // Mix with other audio
                .allowBluetooth,          // Allow Bluetooth headsets
                .allowBluetoothA2DP,      // Allow high-quality Bluetooth
                .defaultToSpeaker,        // Use speaker by default
                .duckOthers               // Duck other audio slightly while recording
            ]
        )

        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.005) // Low latency
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Create a path for the audio file
    private func createAudioFilePath() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioDirectory = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: audioDirectory.path) {
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        }

        // Use .caf extension for PCM format (Core Audio Format)
        let fileName = "thought_\(Date().timeIntervalSince1970).caf"
        return audioDirectory.appendingPathComponent(fileName)
    }

    /// Process audio buffer - calculate levels, write to file, send to transcription
    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        time: AVAudioTime,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) {
        var outputBuffer: AVAudioPCMBuffer

        if let converter = converter {
            // Convert buffer to desired format
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error else { return }
            outputBuffer = convertedBuffer
        } else {
            outputBuffer = buffer
        }

        // Calculate audio level (updates UI on main thread)
        calculateAudioLevel(from: outputBuffer)

        // Write to file if available (thread-safe access)
        audioFileQueue.async { [weak self] in
            if let file = self?._audioFileRef {
                try? file.write(from: outputBuffer)
            }
        }

        // Send to transcription callback
        onAudioBuffer?(outputBuffer, time)
    }

    /// Calculate RMS audio level from buffer
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))

        // Convert to 0-1 range with some smoothing
        let level = min(1.0, rms * 5) // Amplify for visibility

        // Update UI on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Smooth the level changes
            self.audioLevel = self.audioLevel * 0.7 + level * 0.3
        }
    }

    /// Start elapsed time timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(startTime)
            }
        }
    }

    /// Stop elapsed time timer
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }
}

// MARK: - Errors

enum AudioRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case engineCreationFailed
    case inputNodeUnavailable
    case formatCreationFailed
    case converterCreationFailed
    case fileCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .notRecording:
            return "Not currently recording"
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .inputNodeUnavailable:
            return "Audio input is not available"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .fileCreationFailed:
            return "Failed to create audio file"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}

// MARK: - Permission Handling

extension AudioRecordingService {

    /// Check if microphone permission is granted
    static var hasMicrophonePermission: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Request microphone permission
    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Time Formatting

extension AudioRecordingService {

    /// Format elapsed time as MM:SS
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
