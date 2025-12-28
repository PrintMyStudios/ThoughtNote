import Foundation
import AVFoundation

/// Protocol for streaming speech-to-text services
protocol StreamingSpeechToTextService: AnyObject {
    /// Whether the service is currently connected and streaming
    var isStreaming: Bool { get }

    /// Delegate for receiving transcription updates
    var delegate: StreamingSTTDelegate? { get set }

    /// Start the streaming session
    /// - Parameters:
    ///   - sampleRate: Audio sample rate in Hz (e.g., 16000)
    ///   - channels: Number of audio channels (1 for mono)
    func start(sampleRate: Int, channels: Int) async throws

    /// Send audio data to the service
    /// - Parameter pcmData: Raw PCM audio data (16-bit little-endian)
    func sendAudio(_ pcmData: Data)

    /// Stop the streaming session
    func stop() async
}

/// Delegate protocol for receiving transcription updates
protocol StreamingSTTDelegate: AnyObject {
    /// Called when a partial (non-final) transcript is received
    func streamingSTT(_ service: StreamingSpeechToTextService, didReceivePartialTranscript text: String)

    /// Called when a final transcript segment is received
    func streamingSTT(_ service: StreamingSpeechToTextService, didReceiveFinalTranscript text: String)

    /// Called when an error occurs
    func streamingSTT(_ service: StreamingSpeechToTextService, didEncounterError error: Error)

    /// Called when the connection is established
    func streamingSTTDidConnect(_ service: StreamingSpeechToTextService)

    /// Called when the connection is closed
    func streamingSTTDidDisconnect(_ service: StreamingSpeechToTextService)
}

// MARK: - STT Provider Type

enum STTProviderType: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "appleSpeech"
    case assemblyAI = "assemblyAI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech (On-Device)"
        case .assemblyAI: return "AssemblyAI (Cloud)"
        }
    }

    var description: String {
        switch self {
        case .appleSpeech: return "Uses on-device speech recognition when available"
        case .assemblyAI: return "Cloud-based streaming transcription with high accuracy"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .appleSpeech: return false
        case .assemblyAI: return true
        }
    }
}

// MARK: - STT Configuration

struct STTConfiguration {
    var provider: STTProviderType
    var apiKey: String?
    var language: String

    static var `default`: STTConfiguration {
        STTConfiguration(
            provider: .appleSpeech,
            apiKey: nil,
            language: "en-US"
        )
    }
}

// MARK: - STT Errors

enum StreamingSTTError: LocalizedError {
    case notConfigured(String)
    case connectionFailed(String)
    case authenticationFailed
    case streamingError(String)
    case audioFormatError(String)
    case alreadyStreaming
    case notStreaming

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return "STT not configured: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed. Check your API key."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .audioFormatError(let message):
            return "Audio format error: \(message)"
        case .alreadyStreaming:
            return "Already streaming"
        case .notStreaming:
            return "Not currently streaming"
        }
    }
}
