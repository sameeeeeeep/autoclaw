import Foundation
import Speech
import AVFoundation
import CoreAudio

/// Represents an available audio input device.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
}

/// Speech-to-text service with configurable backend.
/// Supports: WhisperKit (local, Neural Engine) or Apple SFSpeech (fallback).
/// WhisperKit records full audio and transcribes on stop (batch mode).
/// Apple Speech streams live partial results (legacy).
@MainActor
final class VoiceService: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var currentTranscript = ""  // live partial (Apple Speech only)
    @Published var finalTranscript = ""    // committed after stop
    @Published var availableMicrophones: [AudioInputDevice] = []

    // MARK: - Backend

    let whisperKitService = WhisperKitService()

    /// Currently active backend (read from settings)
    var activeBackend: STTProvider {
        AppSettings.shared.sttProvider
    }

    /// Callback when a final transcript is ready
    var onTranscriptReady: ((String) -> Void)?

    // MARK: - Apple Speech Private

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Track which backend is currently active (may differ from setting if WhisperKit isn't loaded)
    private var currentBackend: STTProvider = .apple

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        refreshMicrophones()
    }

    // MARK: - Microphone Enumeration

    /// Refresh the list of available audio input devices
    func refreshMicrophones() {
        availableMicrophones = Self.enumerateInputDevices()
    }

    /// The currently selected mic's CoreAudio device ID, or nil for system default
    var selectedDeviceID: AudioDeviceID? {
        guard let uid = AppSettings.shared.selectedMicrophoneUID else { return nil }
        return availableMicrophones.first(where: { $0.uid == uid })?.id
    }

    /// Enumerate all audio input devices via CoreAudio
    static func enumerateInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil, &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        // Get default input device
        var defaultInputID: AudioDeviceID = 0
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0, nil, &defaultSize,
            &defaultInputID
        )

        var results: [AudioInputDevice] = []

        for deviceID in deviceIDs {
            // Check if this device has input channels
            var inputAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputAddr, 0, nil, &inputSize)
            guard status == noErr, inputSize > 0 else { continue }

            let bufferListRaw = UnsafeMutableRawPointer.allocate(byteCount: Int(inputSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bufferListRaw.deallocate() }
            let bufferListPtr = bufferListRaw.bindMemory(to: AudioBufferList.self, capacity: 1)
            status = AudioObjectGetPropertyData(deviceID, &inputAddr, 0, nil, &inputSize, bufferListPtr)
            guard status == noErr else { continue }

            let bufferCount = Int(bufferListPtr.pointee.mNumberBuffers)
            guard bufferCount > 0 else { continue }
            // Check first buffer has input channels
            let firstBuffer = bufferListPtr.pointee.mBuffers
            let inputChannels = Int(firstBuffer.mNumberChannels)
            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &nameRef)

            // Get device UID
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, &uidRef)

            let name = nameRef as String
            let uid = uidRef as String
            guard !name.isEmpty, !uid.isEmpty else { continue }

            results.append(AudioInputDevice(
                id: deviceID,
                uid: uid,
                name: name,
                isDefault: deviceID == defaultInputID
            ))
        }

        return results.sorted { $0.isDefault && !$1.isDefault }
    }

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    // MARK: - Pre-warm

    func warmup() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        print("[VoiceService] Permissions pre-requested")

        // Pre-load WhisperKit model in background
        Task {
            await whisperKitService.setup()
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
        guard !isListening else {
            DebugLog.log("[VoiceService] Already listening, ignoring startListening()")
            return
        }

        currentTranscript = ""
        finalTranscript = ""

        DebugLog.log("[VoiceService] startListening() — backend setting: \(activeBackend.rawValue), whisperKit loaded: \(whisperKitService.isModelLoaded), loading: \(whisperKitService.isLoadingModel)")

        switch activeBackend {
        case .whisperKit:
            if whisperKitService.isModelLoaded {
                currentBackend = .whisperKit
                startWhisperKit()
            } else if whisperKitService.isLoadingModel {
                DebugLog.log("[VoiceService] WhisperKit loading, waiting...")
                currentBackend = .whisperKit
                Task { @MainActor in
                    for _ in 0..<60 {
                        if whisperKitService.isModelLoaded { break }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    if whisperKitService.isModelLoaded {
                        DebugLog.log("[VoiceService] WhisperKit loaded after wait, starting")
                        startWhisperKit()
                    } else {
                        DebugLog.log("[VoiceService] WhisperKit still not loaded, falling back to Apple Speech")
                        currentBackend = .apple
                        startAppleSpeech()
                    }
                }
            } else {
                DebugLog.log("[VoiceService] WhisperKit not loaded, triggering setup...")
                currentBackend = .whisperKit
                Task { @MainActor in
                    await whisperKitService.setup()
                    if whisperKitService.isModelLoaded {
                        DebugLog.log("[VoiceService] WhisperKit setup complete, starting")
                        startWhisperKit()
                    } else {
                        DebugLog.log("[VoiceService] WhisperKit setup failed, falling back to Apple Speech")
                        currentBackend = .apple
                        startAppleSpeech()
                    }
                }
            }
        case .apple:
            currentBackend = .apple
            startAppleSpeech()
        }
    }

    func stopListening() {
        guard isListening else { return }

        switch currentBackend {
        case .whisperKit:
            stopWhisperKit()
        case .apple:
            stopAppleSpeech()
        }
    }

    /// Async stop that waits for WhisperKit transcription to finish.
    /// Returns the full transcript text.
    func stopAndTranscribe() async -> String {
        guard isListening else { return "" }

        switch currentBackend {
        case .whisperKit:
            isListening = false
            let text = await whisperKitService.stopListening()
            finalTranscript = text
            return text
        case .apple:
            stopAppleSpeech()
            return finalTranscript
        }
    }

    // MARK: - WhisperKit Backend

    private func startWhisperKit() {
        isListening = true
        let deviceID = selectedDeviceID
        print("[VoiceService] Starting WhisperKit (batch mode) with mic: \(deviceID.map { String($0) } ?? "default")")

        Task { @MainActor in
            await whisperKitService.startListening(inputDeviceID: deviceID)
            // Sync listening state
            isListening = whisperKitService.isListening
        }
    }

    private func stopWhisperKit() {
        // Use sync stop — fires callback when transcription finishes
        whisperKitService.onTranscriptReady = { [weak self] text in
            self?.finalTranscript = text
            self?.currentTranscript = text
            self?.onTranscriptReady?(text)
        }
        whisperKitService.stopListeningSync()
        isListening = false
        print("[VoiceService] WhisperKit stopped (transcribing...)")
    }

    // MARK: - Apple Speech Backend

    private func startAppleSpeech() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[VoiceService] Speech recognizer not available")
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true

        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

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
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        print("[VoiceService] Recognition error: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Set selected mic if configured
        if let deviceID = selectedDeviceID {
            setAudioEngineInputDevice(deviceID)
        }

        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            print("[VoiceService] Apple Speech listening started (mic: \(selectedDeviceID.map { String($0) } ?? "default"))")
        } catch {
            print("[VoiceService] Audio engine error: \(error)")
            cleanupAppleSpeech()
        }
    }

    private func stopAppleSpeech() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false

        if !currentTranscript.isEmpty && finalTranscript.isEmpty {
            finalTranscript = currentTranscript
            commitTranscript()
        }

        print("[VoiceService] Apple Speech stopped")
    }

    private func commitTranscript() {
        let text = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        print("[VoiceService] Transcript: \(text)")
        onTranscriptReady?(text)
    }

    private func cleanupAppleSpeech() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Set AVAudioEngine input device via CoreAudio HAL
    private func setAudioEngineInputDevice(_ deviceID: AudioDeviceID) {
        let audioUnit = audioEngine.inputNode.audioUnit!
        var devID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("[VoiceService] Failed to set input device \(deviceID): \(status)")
        } else {
            print("[VoiceService] Set input device to \(deviceID)")
        }
    }

    deinit {
        recognitionTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}
