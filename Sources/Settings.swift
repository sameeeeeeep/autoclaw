import Foundation

// MARK: - Cleanup Provider

/// Which model handles transcript cleanup (filler removal, grammar fix) before injection.
enum CleanupProvider: String, CaseIterable, Identifiable {
    case qwen = "Qwen (local)"
    case haiku = "Haiku (cloud)"
    case none = "None (raw)"

    var id: String { rawValue }
}

// MARK: - Enhance Provider

/// Which model handles smart enhancement (context-aware rewrite) after injection.
enum EnhanceProvider: String, CaseIterable, Identifiable {
    case haiku = "Haiku"
    case sonnet = "Sonnet"
    case none = "None"

    var id: String { rawValue }

    /// The model flag to pass to claude CLI
    var modelFlag: String {
        switch self {
        case .haiku: return "haiku"
        case .sonnet: return "sonnet"
        case .none: return ""
        }
    }
}

// MARK: - STT Provider

/// Which speech-to-text engine to use.
enum STTProvider: String, CaseIterable, Identifiable {
    case whisperKit = "WhisperKit (local)"
    case apple = "Apple Speech"

    var id: String { rawValue }
}

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let key = "anthropic_api_key"
    private let cleanupKey = "cleanup_provider"
    private let enhanceKey = "enhance_provider"
    private let sttKey = "stt_provider"
    private let micKey = "selected_microphone_uid"
    private let dialogThemeKey = "dialog_theme_id"

    var anthropicAPIKey: String {
        // 1. Environment variable
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return sanitizeKey(env)
        }
        // 2. UserDefaults
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        return sanitizeKey(stored)
    }

    func setAnthropicAPIKey(_ value: String) {
        let clean = sanitizeKey(value)
        UserDefaults.standard.set(clean, forKey: key)
        UserDefaults.standard.synchronize()
        print("[Autoclaw] API key saved (length: \(clean.count))")
    }

    /// Which provider cleans up transcripts before cursor injection
    var cleanupProvider: CleanupProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: cleanupKey) ?? ""
            return CleanupProvider(rawValue: raw) ?? .qwen
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: cleanupKey)
            print("[Autoclaw] Cleanup provider -> \(newValue.rawValue)")
        }
    }

    /// Which provider handles smart enhancement after injection
    var enhanceProvider: EnhanceProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: enhanceKey) ?? ""
            return EnhanceProvider(rawValue: raw) ?? .haiku
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: enhanceKey)
            print("[Autoclaw] Enhance provider -> \(newValue.rawValue)")
        }
    }

    /// Which STT engine to use
    var sttProvider: STTProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: sttKey) ?? ""
            return STTProvider(rawValue: raw) ?? .whisperKit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sttKey)
            print("[Autoclaw] STT provider -> \(newValue.rawValue)")
        }
    }

    /// Selected microphone unique ID (nil = system default)
    var selectedMicrophoneUID: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: micKey) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: micKey)
            print("[Autoclaw] Microphone -> \(newValue ?? "system default")")
        }
    }

    /// Which TV character pair provides the ELI5 session dialog
    var dialogThemeId: String {
        get { UserDefaults.standard.string(forKey: dialogThemeKey) ?? "gilfoyle-dinesh" }
        set {
            UserDefaults.standard.set(newValue, forKey: dialogThemeKey)
            print("[Autoclaw] Dialog theme -> \(newValue)")
        }
    }

    /// Strip whitespace, newlines, and other junk that gets pasted with the key
    private func sanitizeKey(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
