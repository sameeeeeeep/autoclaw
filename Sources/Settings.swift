import Foundation

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let key = "anthropic_api_key"

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

    /// Strip whitespace, newlines, and other junk that gets pasted with the key
    private func sanitizeKey(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
