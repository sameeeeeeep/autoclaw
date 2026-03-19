import Foundation
import Speech
import AVFoundation

/// Simple on-device speech-to-text using Apple's Speech framework.
/// Double-tap Caps Lock to start/stop. Transcribed text appears in the thread.
@MainActor
final class VoiceService: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var currentTranscript = ""  // live partial transcript
    @Published var finalTranscript = ""    // committed after stop

    // MARK: - Private

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Callback when a final transcript is ready
    var onTranscriptReady: ((String) -> Void)?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("[VoiceService] Speech recognition authorized")
                    completion(true)
                case .denied:
                    print("[VoiceService] Speech recognition denied")
                    completion(false)
                case .restricted:
                    print("[VoiceService] Speech recognition restricted")
                    completion(false)
                case .notDetermined:
                    print("[VoiceService] Speech recognition not determined")
                    completion(false)
                @unknown default:
                    completion(false)
                }
            }
        }
    }

    // MARK: - Start / Stop

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[VoiceService] Speech recognizer not available")
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        currentTranscript = ""
        finalTranscript = ""

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true

        // Use on-device recognition if available (macOS 13+)
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            if recognizer.supportsOnDeviceRecognition {
                print("[VoiceService] Using on-device recognition")
            }
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.currentTranscript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.finalTranscript = result.bestTranscription.formattedString
                        self.commitTranscript()
                    }
                }

                if let error = error {
                    // Ignore cancellation errors
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        print("[VoiceService] Recognition error: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Install audio tap — pass nil for format to let AVAudioEngine
        // use the hardware's native format, avoiding sample rate mismatch
        // crashes (e.g. 24kHz mic vs 48kHz output)
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            print("[VoiceService] Listening started")
        } catch {
            print("[VoiceService] Audio engine error: \(error)")
            cleanup()
        }
    }

    func stopListening() {
        guard isListening else { return }

        // Stop audio
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        isListening = false
        print("[VoiceService] Listening stopped")

        // If we have a partial transcript, commit it
        if !currentTranscript.isEmpty && finalTranscript.isEmpty {
            finalTranscript = currentTranscript
            commitTranscript()
        }
    }

    private func commitTranscript() {
        let text = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        print("[VoiceService] Transcript: \(text)")
        onTranscriptReady?(text)
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    deinit {
        recognitionTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}
