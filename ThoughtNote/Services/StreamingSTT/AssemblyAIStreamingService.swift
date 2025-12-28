import Foundation
import AVFoundation

/// AssemblyAI Universal Streaming speech-to-text service
/// Uses WebSocket for real-time streaming transcription
final class AssemblyAIStreamingService: NSObject, StreamingSpeechToTextService {

    // MARK: - Properties

    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?

    private(set) var isStreaming = false
    weak var delegate: StreamingSTTDelegate?

    // Configuration
    private var sampleRate: Int = 16000
    private var channels: Int = 1

    // Buffer for accumulating audio data
    private let audioQueue = DispatchQueue(label: "com.thoughtnote.assemblyai.audio")
    private var audioBuffer = Data()
    private let sendInterval: TimeInterval = 0.25 // Send audio every 250ms
    private var sendTimer: Timer?

    // MARK: - Constants

    private static let baseURL = "wss://api.assemblyai.com/v2/realtime/ws"

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    // MARK: - StreamingSpeechToTextService

    func start(sampleRate: Int, channels: Int) async throws {
        guard !isStreaming else {
            throw StreamingSTTError.alreadyStreaming
        }

        guard !apiKey.isEmpty else {
            throw StreamingSTTError.notConfigured("AssemblyAI API key is required")
        }

        self.sampleRate = sampleRate
        self.channels = channels

        // Build WebSocket URL with parameters
        var urlComponents = URLComponents(string: Self.baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(sampleRate))
        ]

        guard let url = urlComponents.url else {
            throw StreamingSTTError.connectionFailed("Invalid URL")
        }

        // Create WebSocket request with authentication
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        // Create URL session and WebSocket task
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: request)

        // Start connection
        webSocketTask?.resume()

        // Wait for connection to be established
        try await waitForConnection()

        // Start receiving messages
        startReceiving()

        // Start send timer for buffered audio
        await MainActor.run {
            startSendTimer()
        }

        isStreaming = true
        delegate?.streamingSTTDidConnect(self)
    }

    func sendAudio(_ pcmData: Data) {
        guard isStreaming else { return }

        audioQueue.async { [weak self] in
            self?.audioBuffer.append(pcmData)
        }
    }

    func stop() async {
        guard isStreaming else { return }

        isStreaming = false

        // Stop send timer
        await MainActor.run {
            sendTimer?.invalidate()
            sendTimer = nil
        }

        // Cancel receive task
        receiveTask?.cancel()
        receiveTask = nil

        // Send terminate message
        let terminateMessage = TerminateMessage(terminateSession: true)
        if let data = try? JSONEncoder().encode(terminateMessage),
           let jsonString = String(data: data, encoding: .utf8) {
            try? await webSocketTask?.send(.string(jsonString))
        }

        // Close WebSocket
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Clear buffer
        audioQueue.sync {
            audioBuffer.removeAll()
        }

        delegate?.streamingSTTDidDisconnect(self)
    }

    // MARK: - Private Methods

    private func waitForConnection() async throws {
        // Send a ping to verify connection
        do {
            try await webSocketTask?.sendPing()
        } catch {
            throw StreamingSTTError.connectionFailed(error.localizedDescription)
        }
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            while let self = self, self.isStreaming, !Task.isCancelled {
                do {
                    guard let message = try await self.webSocketTask?.receive() else { break }
                    self.handleMessage(message)
                } catch {
                    if !Task.isCancelled && self.isStreaming {
                        self.delegate?.streamingSTT(self, didEncounterError: error)
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTranscriptMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTranscriptMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseTranscriptMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(TranscriptResponse.self, from: data)

            switch response.messageType {
            case "SessionBegins":
                // Session started successfully
                break

            case "PartialTranscript":
                if let transcript = response.text, !transcript.isEmpty {
                    delegate?.streamingSTT(self, didReceivePartialTranscript: transcript)
                }

            case "FinalTranscript":
                if let transcript = response.text, !transcript.isEmpty {
                    delegate?.streamingSTT(self, didReceiveFinalTranscript: transcript)
                }

            case "SessionTerminated":
                // Session ended
                Task {
                    await stop()
                }

            case "Error", "error":
                let errorMessage = response.error ?? "Unknown error"
                delegate?.streamingSTT(self, didEncounterError: StreamingSTTError.streamingError(errorMessage))

            default:
                break
            }
        } catch {
            // Try to parse as error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                delegate?.streamingSTT(self, didEncounterError: StreamingSTTError.streamingError(errorResponse.error))
            }
        }
    }

    private func startSendTimer() {
        sendTimer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            self?.flushAudioBuffer()
        }
    }

    private func flushAudioBuffer() {
        guard isStreaming else { return }

        var dataToSend: Data?
        audioQueue.sync {
            if !audioBuffer.isEmpty {
                dataToSend = audioBuffer
                audioBuffer.removeAll()
            }
        }

        guard let data = dataToSend else { return }

        // Convert to base64 and send as JSON
        let base64Audio = data.base64EncodedString()
        let audioMessage = AudioMessage(audioData: base64Audio)

        Task {
            do {
                let jsonData = try JSONEncoder().encode(audioMessage)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    try await webSocketTask?.send(.string(jsonString))
                }
            } catch {
                // Silently fail for audio send errors during streaming
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension AssemblyAIStreamingService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Connection opened
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if isStreaming {
            isStreaming = false
            delegate?.streamingSTTDidDisconnect(self)
        }
    }
}

// MARK: - Message Types

private struct AudioMessage: Codable {
    let audioData: String

    enum CodingKeys: String, CodingKey {
        case audioData = "audio_data"
    }
}

private struct TerminateMessage: Codable {
    let terminateSession: Bool

    enum CodingKeys: String, CodingKey {
        case terminateSession = "terminate_session"
    }
}

private struct TranscriptResponse: Codable {
    let messageType: String
    let text: String?
    let confidence: Double?
    let audioStart: Int?
    let audioEnd: Int?
    let words: [Word]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case text
        case confidence
        case audioStart = "audio_start"
        case audioEnd = "audio_end"
        case words
        case error
    }

    struct Word: Codable {
        let text: String
        let start: Int
        let end: Int
        let confidence: Double
    }
}

private struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Audio Conversion Helper

extension AssemblyAIStreamingService {

    /// Convert AVAudioPCMBuffer to 16-bit little-endian PCM Data
    static func convertToInt16PCM(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        var int16Data = Data(count: frameLength * 2) // 2 bytes per sample

        int16Data.withUnsafeMutableBytes { rawPtr in
            guard let int16Ptr = rawPtr.bindMemory(to: Int16.self).baseAddress else { return }

            for i in 0..<frameLength {
                // Convert float (-1.0 to 1.0) to Int16 (-32768 to 32767)
                let floatSample = floatData.pointee[i]
                let clampedSample = max(-1.0, min(1.0, floatSample))
                let int16Sample = Int16(clampedSample * Float(Int16.max))
                int16Ptr[i] = int16Sample.littleEndian
            }
        }

        return int16Data
    }
}
