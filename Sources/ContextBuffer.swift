import Foundation

// MARK: - Context Buffer

/// 60-second sliding window that aggregates all sensor text into a single buffer
/// for Qwen to evaluate. Events are text-only, capped in size, and auto-expire.
@MainActor
final class ContextBuffer: ObservableObject {

    // MARK: - Types

    struct BufferEntry {
        let timestamp: Date
        let source: Source
        let text: String

        enum Source: String {
            case appSwitch  = "APP"
            case clipboard  = "CLIP"
            case ocr        = "OCR"
            case browser    = "WEB"
            case file       = "FILE"
            case click      = "CLICK"
        }
    }

    // MARK: - Config

    static let windowDuration: TimeInterval = 60   // 60s sliding window
    static let maxTokenBudget = 800                 // ~800 tokens for Qwen prompt
    static let maxEntries = 50                      // hard cap on entries

    // MARK: - State

    @Published var entries: [BufferEntry] = []
    @Published var lastEventAt: Date?

    /// Snapshot of the buffer as a formatted text block for LLM consumption
    var snapshot: String {
        pruneExpired()
        let lines = entries.map { entry in
            let age = Int(Date().timeIntervalSince(entry.timestamp))
            return "[\(entry.source.rawValue) \(age)s ago] \(entry.text)"
        }
        // Truncate to fit token budget (~4 chars per token)
        let maxChars = Self.maxTokenBudget * 4
        var result = ""
        for line in lines {
            if result.count + line.count + 1 > maxChars { break }
            result += line + "\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the buffer has enough signal to be worth evaluating
    var hasSignal: Bool {
        pruneExpired()
        return entries.count >= 2
    }

    // MARK: - Ingest

    func recordAppSwitch(app: String, window: String?, url: String?) {
        var text = "Switched to \(app)"
        if let w = window, !w.isEmpty { text += " — \(w)" }
        if let u = url, !u.isEmpty { text += " (\(u))" }
        append(.appSwitch, text: String(text.prefix(200)))
    }

    func recordClipboard(content: String, sourceApp: String) {
        let preview = String(content.prefix(300))
        append(.clipboard, text: "Copied from \(sourceApp): \(preview)")
    }

    func recordOCR(text: String, app: String) {
        guard !text.isEmpty else { return }
        let preview = String(text.prefix(150))
        append(.ocr, text: "Screen (\(app)): \(preview)")
    }

    func recordBrowserEvent(type: String, page: String?, detail: String?) {
        var text = "Browser \(type)"
        if let p = page { text += " on \(p)" }
        if let d = detail { text += ": \(d)" }
        append(.browser, text: String(text.prefix(200)))
    }

    func recordFileEvent(fileName: String, operation: String, app: String) {
        append(.file, text: "\(app) \(operation) \(fileName)")
    }

    func recordClick(app: String, ocrContext: String?) {
        var text = "Clicked in \(app)"
        if let ocr = ocrContext { text += " near: \(ocr)" }
        append(.click, text: String(text.prefix(200)))
    }

    // MARK: - Private

    private func append(_ source: BufferEntry.Source, text: String) {
        let entry = BufferEntry(timestamp: Date(), source: source, text: text)
        entries.append(entry)
        lastEventAt = Date()
        // Hard cap
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.windowDuration)
        entries.removeAll { $0.timestamp < cutoff }
    }

    func clear() {
        entries.removeAll()
        lastEventAt = nil
    }
}
