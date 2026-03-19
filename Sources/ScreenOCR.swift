import AppKit
import Vision

/// Performs OCR on a screen capture using Apple's Vision framework,
/// returning recognized text ranked by proximity to the cursor position.
struct ScreenOCR {

    /// A single recognized text observation with its screen-relative position.
    struct TextObservation {
        let text: String
        let boundingBox: CGRect      // normalized (0-1) in Vision coordinates (origin bottom-left)
        let confidence: Float
        let distanceToCursor: CGFloat // distance from center of bounding box to cursor (in normalized coords)
    }

    /// Run OCR on a CGImage and return text ranked by proximity to the cursor.
    /// - Parameters:
    ///   - image: The screen capture image
    ///   - cursorLocation: Cursor position in screen coordinates (origin bottom-left, as from NSEvent.mouseLocation)
    ///   - imageSize: The full screen/image size in points
    /// - Returns: Recognized text observations sorted by distance to cursor (nearest first)
    static func recognizeText(
        in image: CGImage,
        cursorLocation: CGPoint,
        imageSize: CGSize
    ) -> [TextObservation] {
        // Normalize cursor to 0-1 range (Vision uses bottom-left origin, same as NSEvent.mouseLocation)
        let normalizedCursor = CGPoint(
            x: cursorLocation.x / imageSize.width,
            y: cursorLocation.y / imageSize.height
        )

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate  // accurate catches more UI text than .fast
        request.usesLanguageCorrection = true  // helps with small/partial UI labels

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DebugLog.log("[ScreenOCR] Vision error: \(error)")
            return []
        }

        guard let results = request.results else {
            DebugLog.log("[ScreenOCR] No results from Vision")
            return []
        }
        DebugLog.log("[ScreenOCR] Found \(results.count) text observations, cursor=(\(String(format: "%.2f", normalizedCursor.x)), \(String(format: "%.2f", normalizedCursor.y)))")

        var observations: [TextObservation] = []

        for result in results {
            guard let candidate = result.topCandidates(1).first else { continue }
            let box = result.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            let dx = center.x - normalizedCursor.x
            let dy = center.y - normalizedCursor.y
            let distance = sqrt(dx * dx + dy * dy)

            observations.append(TextObservation(
                text: candidate.string,
                boundingBox: box,
                confidence: candidate.confidence,
                distanceToCursor: distance
            ))
        }

        // Sort by distance to cursor (nearest first)
        observations.sort { $0.distanceToCursor < $1.distanceToCursor }

        return observations
    }

    /// Build a concise context string from OCR results for embedding in events.
    /// Prioritizes text near the cursor, includes a summary of surrounding text.
    /// Filters out common macOS UI chrome noise before building context.
    /// - Parameters:
    ///   - observations: Sorted OCR observations (nearest to cursor first)
    ///   - nearbyCount: How many "near cursor" items to include in detail
    ///   - nearbyThreshold: Max normalized distance to consider "near" (0-1 diagonal, ~0.15 is about 15% of screen)
    ///   - maxLength: Truncate final string to this length
    static func buildContext(
        from observations: [TextObservation],
        nearbyCount: Int = 5,
        nearbyThreshold: CGFloat = 0.25,
        maxLength: Int = 600
    ) -> String? {
        guard !observations.isEmpty else { return nil }

        // Filter out noise before building context
        let filtered = observations.filter { !isNoise($0.text) }
        guard !filtered.isEmpty else { return nil }

        var parts: [String] = []

        // Near cursor: closest items within threshold
        let nearby = filtered.prefix(nearbyCount).filter { $0.distanceToCursor <= nearbyThreshold }
        if !nearby.isEmpty {
            let labels = nearby.map { $0.text }
            parts.append("Near cursor: \(labels.joined(separator: " | "))")
        }

        // All remaining observations as ambient screen context
        let nearbyUsed = nearby.count
        let remaining = filtered.dropFirst(nearbyUsed).prefix(20)
        if !remaining.isEmpty {
            let ambient = remaining.map { $0.text }
            parts.append("On screen: \(ambient.joined(separator: " | "))")
        }

        // If nothing passed nearby threshold, just dump everything as "On screen"
        if parts.isEmpty {
            let all = filtered.prefix(20).map { $0.text }
            parts.append("On screen: \(all.joined(separator: " | "))")
        }

        let result = parts.joined(separator: "\n")
        if result.count > maxLength {
            return String(result.prefix(maxLength)) + "…"
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - OCR Noise Filter

    /// Returns true if the text is common macOS UI chrome that adds no semantic value.
    private static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short to be meaningful (single chars, punctuation)
        if trimmed.count <= 1 { return true }

        // Exact matches — common macOS menu bar items, window controls, status bar
        if noiseExactMatch.contains(trimmed) { return true }

        // Case-insensitive exact matches
        let lower = trimmed.lowercased()
        if noiseLowerExactMatch.contains(lower) { return true }

        // Autoclaw's own UI text
        if lower.contains("autoclaw") || lower.contains("recording workflow") || lower.contains("stop + save") { return true }

        // Timestamp-like strings (e.g. "12:34", "2:05 PM", "Mon 12:34")
        if trimmed.range(of: "^\\d{1,2}:\\d{2}(:\\d{2})?( [AP]M)?$", options: .regularExpression) != nil { return true }
        if trimmed.range(of: "^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s+\\d", options: .regularExpression) != nil { return true }

        // Battery/wifi status strings
        if trimmed.range(of: "^\\d{1,3}%$", options: .regularExpression) != nil { return true }

        return false
    }

    /// macOS menu bar, window chrome, and system UI — exact string matches
    private static let noiseExactMatch: Set<String> = [
        // Menu bar items
        "File", "Edit", "View", "Window", "Help", "Go", "Format",
        "Insert", "Tools", "Table", "Arrange", "Share", "Bookmarks",
        "History", "Developer", "Debug", "Product", "Source Control",
        "Editor", "Navigate", "Find", "Selection",
        // Window controls
        "Close", "Minimize", "Zoom", "Enter Full Screen", "Exit Full Screen",
        // Common toolbar
        "Back", "Forward", "Reload", "Downloads",
        // Status bar / system
        "Wi-Fi", "Bluetooth", "Battery", "Control Center", "Siri",
        "Spotlight", "Notification Center", "Do Not Disturb", "Focus",
        // Dock labels (single-word app names are too ambiguous to filter)
        "Finder", "Launchpad", "System Settings", "System Preferences",
        // Generic button labels that appear everywhere
        "OK", "Cancel", "Done", "Apply", "Save", "Undo", "Redo",
    ]

    /// Lowercase matches for case-insensitive filtering
    private static let noiseLowerExactMatch: Set<String> = [
        "file", "edit", "view", "window", "help", "go", "format",
        "insert", "tools", "table", "arrange", "share", "bookmarks",
        "history", "developer", "debug", "product", "source control",
        "editor", "navigate", "find", "selection",
        "close", "minimize", "zoom",
        "wi-fi", "bluetooth", "battery", "control center", "siri",
        "spotlight", "notification center", "do not disturb", "focus",
        "finder", "launchpad", "system settings", "system preferences",
        "ok", "cancel", "done", "apply", "save", "undo", "redo",
        "haiku", "sonnet", "opus", "learn", "execute",
    ]
}
