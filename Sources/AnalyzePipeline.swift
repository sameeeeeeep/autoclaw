import Foundation
import Combine

// MARK: - Analyze Pipeline

/// Orchestrates the Analyze mode intelligence chain:
/// Sensors → ContextBuffer → Qwen (bouncer) → Haiku (router) → Toast
///
/// Event-driven, not timer-based. Fires when sensors report activity,
/// with debounce + cooldown to avoid spamming.
@MainActor
final class AnalyzePipeline: ObservableObject {

    // MARK: - Config

    static let debounceInterval: TimeInterval = 5     // wait 5s after last event before triggering
    static let cooldownInterval: TimeInterval = 60    // min 60s between Qwen calls
    static let maxCallsPerHour = 20                   // hard cap on Qwen calls
    static let confidenceThreshold = 0.6              // discard below this

    // MARK: - State

    @Published var isAnalyzing = false
    @Published var lastDetection: Detection?

    /// Callback when a detection is ready for toast
    var onDetection: ((Detection) -> Void)?

    // MARK: - Types

    struct Detection {
        let type: DetectionType
        let description: String
        let source: String          // which sensor triggered
        let confidence: Double
        let suggestedAction: String
        let fulfilmentPlan: FulfilmentPlan?

        var shouldSurface: Bool { confidence >= 0.6 }
    }

    enum DetectionType: String, Codable {
        case task       // "there's something to DO"
        case workflow   // "user is repeating a pattern"
        case none       // nothing actionable
    }

    struct FulfilmentPlan {
        let route: FulfilmentRoute
        let toolName: String?
        let templateName: String?
        let steps: [String]
    }

    enum FulfilmentRoute: String {
        case template       // matched a pre-loaded or learned workflow template
        case mcpTool        // matched an installed MCP tool
        case claudeCustom   // no match, Claude figures it out
    }

    // MARK: - Dependencies

    private let contextBuffer: ContextBuffer
    private let ollamaService: OllamaService
    private let capabilityMap: CapabilityMap
    private let workflowStore: WorkflowStore

    // MARK: - Rate Limiting

    private var lastQwenCallAt: Date?
    private var callsThisHour: Int = 0
    private var callsHourStart: Date = Date()

    // MARK: - Debounce

    private var debounceTask: Task<Void, Never>?

    init(contextBuffer: ContextBuffer, ollamaService: OllamaService,
         capabilityMap: CapabilityMap, workflowStore: WorkflowStore) {
        self.contextBuffer = contextBuffer
        self.ollamaService = ollamaService
        self.capabilityMap = capabilityMap
        self.workflowStore = workflowStore
    }

    // MARK: - Trigger

    /// Called when any sensor reports an event. Debounces before evaluating.
    func onSensorEvent() {
        // Cancel previous debounce
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await evaluate()
        }
    }

    // MARK: - Evaluate (Qwen → Haiku)

    private func evaluate() async {
        guard canCallQwen() else { return }
        guard contextBuffer.hasSignal else { return }

        let bufferSnapshot = contextBuffer.snapshot
        guard !bufferSnapshot.isEmpty else { return }

        isAnalyzing = true
        recordQwenCall()

        // Step 1: Ask Qwen — "is anything actionable here?"
        let qwenResult = await callQwen(buffer: bufferSnapshot)

        guard let qwen = qwenResult, qwen.type != .none, qwen.confidence >= Self.confidenceThreshold else {
            isAnalyzing = false
            return
        }

        // Step 2: Route via Haiku — match against capabilities, build plan
        let plan = await routeWithHaiku(
            detection: qwen,
            buffer: bufferSnapshot
        )

        let detection = Detection(
            type: qwen.type,
            description: qwen.description,
            source: qwen.source,
            confidence: qwen.confidence,
            suggestedAction: plan?.steps.first ?? qwen.description,
            fulfilmentPlan: plan
        )

        lastDetection = detection
        isAnalyzing = false

        if detection.shouldSurface {
            onDetection?(detection)
            print("[AnalyzePipeline] Detection surfaced: \(detection.description) (conf: \(detection.confidence))")
        }
    }

    // MARK: - Qwen Bouncer

    private struct QwenResponse {
        let type: DetectionType
        let description: String
        let source: String
        let confidence: Double
    }

    private func callQwen(buffer: String) async -> QwenResponse? {
        let prompt = """
        Analyze this 60-second activity log from a macOS user. Determine if anything actionable is happening.

        ACTIVITY LOG:
        \(buffer)

        Respond with EXACTLY one JSON object (no other text):
        {"type":"task|workflow|none","description":"what you detected","source":"which event triggered this","confidence":0.0}

        Rules:
        - "task": there's something specific to DO (message to respond to, task to complete, reminder to act on)
        - "workflow": user is repeating a pattern (app-switch loop, copy-paste cycle, manual data transfer)
        - "none": nothing actionable, user is just browsing/reading
        - confidence: 0.0-1.0 (be conservative, >0.6 means you're quite sure)
        - Be brief in description (max 20 words)
        """

        do {
            let raw = try await ollamaService.generate(
                prompt: prompt,
                system: "You are a fast activity classifier. Output ONLY valid JSON, nothing else."
            )
            return parseQwenResponse(raw)
        } catch {
            print("[AnalyzePipeline] Qwen call failed: \(error)")
            return nil
        }
    }

    private func parseQwenResponse(_ raw: String) -> QwenResponse? {
        // Extract JSON from response (Qwen sometimes wraps in markdown)
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[AnalyzePipeline] Failed to parse Qwen JSON: \(raw.prefix(200))")
            return nil
        }

        let typeStr = json["type"] as? String ?? "none"
        let type: DetectionType
        switch typeStr {
        case "task": type = .task
        case "workflow": type = .workflow
        default: type = .none
        }

        return QwenResponse(
            type: type,
            description: json["description"] as? String ?? "",
            source: json["source"] as? String ?? "",
            confidence: json["confidence"] as? Double ?? 0.0
        )
    }

    // MARK: - Haiku Router

    private func routeWithHaiku(detection: QwenResponse, buffer: String) async -> FulfilmentPlan? {
        // Check templates first (no Haiku needed for exact matches)
        if let templateMatch = matchTemplate(detection: detection) {
            return templateMatch
        }

        // Check MCP capabilities
        if let mcpMatch = matchMCPCapability(detection: detection) {
            return mcpMatch
        }

        // Fall through to Claude custom
        return FulfilmentPlan(
            route: .claudeCustom,
            toolName: nil,
            templateName: nil,
            steps: [detection.description]
        )
    }

    /// Match against learned workflows and pre-loaded templates
    private func matchTemplate(detection: QwenResponse) -> FulfilmentPlan? {
        let desc = detection.description.lowercased()

        // Check learned workflows
        for workflow in workflowStore.workflows {
            let name = workflow.name.lowercased()
            let stepDescs = workflow.steps.map { $0.description.lowercased() }
            if desc.contains(name) || stepDescs.contains(where: { desc.contains($0) }) {
                return FulfilmentPlan(
                    route: .template,
                    toolName: nil,
                    templateName: workflow.name,
                    steps: workflow.steps.map(\.description)
                )
            }
        }

        // Check pre-loaded templates
        for template in PreloadedTemplates.all {
            if template.matches(detection.description) {
                return FulfilmentPlan(
                    route: .template,
                    toolName: template.toolName,
                    templateName: template.name,
                    steps: template.steps
                )
            }
        }

        return nil
    }

    /// Match against installed MCP capabilities
    private func matchMCPCapability(detection: QwenResponse) -> FulfilmentPlan? {
        let desc = detection.description.lowercased()

        // Look through capabilities for a match
        for cap in capabilityMap.capabilities where cap.isInstalled {
            let capDesc = (cap.name + " " + cap.description + " " + cap.sourceApp).lowercased()
            // Simple keyword overlap check
            let words = desc.split(separator: " ").map(String.init)
            let matches = words.filter { capDesc.contains($0) }.count
            if matches >= 2 {
                return FulfilmentPlan(
                    route: .mcpTool,
                    toolName: cap.provider,
                    templateName: nil,
                    steps: ["Use \(cap.name) via \(cap.provider)"]
                )
            }
        }

        return nil
    }

    // MARK: - Rate Limiting

    private func canCallQwen() -> Bool {
        // Reset hourly counter if needed
        if Date().timeIntervalSince(callsHourStart) > 3600 {
            callsThisHour = 0
            callsHourStart = Date()
        }

        // Hard cap
        if callsThisHour >= Self.maxCallsPerHour { return false }

        // Cooldown
        if let last = lastQwenCallAt, Date().timeIntervalSince(last) < Self.cooldownInterval {
            return false
        }

        return true
    }

    private func recordQwenCall() {
        lastQwenCallAt = Date()
        callsThisHour += 1
    }
}
