import Foundation

/// Discovers new capabilities by searching the web when friction is detected
/// but no installed capability can resolve it.
///
/// When the FrictionDetector finds the user manually moving data between
/// App A and App B but there's no MCP server installed, CapabilityDiscovery
/// searches for integrations, APIs, and MCP servers that could bridge them.
@MainActor
final class CapabilityDiscovery {

    // MARK: - Types

    struct DiscoveryResult {
        let query: String
        let sourceApp: String
        let targetApp: String
        let findings: [Finding]
        let timestamp: Date
    }

    struct Finding {
        let name: String           // "Notion MCP Server", "Zapier Notion↔Sheets"
        let type: FindingType
        let description: String
        let url: String?           // where to get it
        let installable: Bool      // can be set up via Claude Code
    }

    enum FindingType: String {
        case mcpServer      // an MCP server that could be installed
        case api            // a direct API integration
        case zapier         // Zapier/Make automation
        case native         // built-in feature of one of the apps
        case workaround     // a manual-but-faster approach
    }

    // MARK: - Discovery Cache

    private var cache: [String: DiscoveryResult] = [:]
    private var inProgress: Set<String> = []

    private let runner: ClaudeCodeRunner
    private let capabilityMap: CapabilityMap

    init(runner: ClaudeCodeRunner, capabilityMap: CapabilityMap) {
        self.runner = runner
        self.capabilityMap = capabilityMap
    }

    // MARK: - Discover

    /// Search for capabilities that could bridge two apps.
    /// Uses Claude Code with web search to find MCP servers, APIs, and integrations.
    func discover(
        sourceApp: String,
        targetApp: String,
        frictionDescription: String
    ) async -> DiscoveryResult? {
        let cacheKey = "\(sourceApp.lowercased())→\(targetApp.lowercased())"

        // Check cache (results valid for 24 hours)
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 86400 {
            return cached
        }

        // Prevent duplicate searches
        guard !inProgress.contains(cacheKey) else { return nil }
        inProgress.insert(cacheKey)
        defer { inProgress.remove(cacheKey) }

        let prompt = buildDiscoveryPrompt(
            sourceApp: sourceApp,
            targetApp: targetApp,
            frictionDescription: frictionDescription
        )

        do {
            var output = ""
            for try await chunk in runner.executeDirect(
                prompt: prompt,
                project: Project(id: UUID(), name: "capability-discovery", path: NSTemporaryDirectory()),
                model: .haiku,
                sessionId: nil,
                singleShot: true
            ) {
                output += chunk
            }

            let findings = parseFindings(from: output)
            let result = DiscoveryResult(
                query: "\(sourceApp) → \(targetApp)",
                sourceApp: sourceApp,
                targetApp: targetApp,
                findings: findings,
                timestamp: Date()
            )

            cache[cacheKey] = result

            // Add discovered capabilities to the map
            for finding in findings {
                let capability = CapabilityMap.Capability(
                    name: finding.name,
                    provider: "Discovered: \(finding.type.rawValue)",
                    sourceApp: sourceApp,
                    targetApp: targetApp,
                    actions: inferActions(from: finding),
                    description: finding.description,
                    isInstalled: false,
                    discoveredFrom: finding.url
                )
                capabilityMap.addDiscovered(capability)
            }

            DebugLog.log("[CapabilityDiscovery] Found \(findings.count) capabilities for \(sourceApp) → \(targetApp)")
            return result

        } catch {
            DebugLog.log("[CapabilityDiscovery] Search failed for \(sourceApp) → \(targetApp): \(error)")
            return nil
        }
    }

    /// Quick check: is it worth searching for capabilities between these apps?
    func shouldDiscover(sourceApp: String, targetApp: String) -> Bool {
        let cacheKey = "\(sourceApp.lowercased())→\(targetApp.lowercased())"

        // Already cached
        if cache[cacheKey] != nil { return false }

        // Already have installed capabilities
        if !capabilityMap.capabilities(from: sourceApp, to: targetApp).isEmpty { return false }

        // Skip internal/system apps
        let skipApps = ["Finder", "System Settings", "Activity Monitor", "Terminal", "Autoclaw"]
        if skipApps.contains(sourceApp) || skipApps.contains(targetApp) { return false }

        return true
    }

    // MARK: - Prompt

    private func buildDiscoveryPrompt(sourceApp: String, targetApp: String, frictionDescription: String) -> String {
        """
        Search the web for ways to automate data transfer between \(sourceApp) and \(targetApp).

        Context: A user is manually \(frictionDescription). I need to find if there are tools, \
        APIs, or integrations that could automate this.

        Search for:
        1. MCP servers (Model Context Protocol) that connect to \(sourceApp) or \(targetApp)
        2. Direct API integrations between \(sourceApp) and \(targetApp)
        3. Zapier/Make/n8n templates for \(sourceApp) ↔ \(targetApp)
        4. Built-in export/import features in either app

        For each finding, respond with a JSON array:
        [
          {
            "name": "Name of the integration",
            "type": "mcp_server|api|zapier|native|workaround",
            "description": "What it does and how it helps",
            "url": "https://...",
            "installable": true
          }
        ]

        Only include findings that are real and currently available. Do not invent integrations.
        If you find nothing, return an empty array: []
        """
    }

    // MARK: - Parse

    private func parseFindings(from output: String) -> [Finding] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON array
        guard let jsonStart = trimmed.range(of: "["),
              let jsonEnd = trimmed.range(of: "]", options: .backwards) else {
            return []
        }

        let jsonStr = String(trimmed[jsonStart.lowerBound...jsonEnd.upperBound])
        guard let data = jsonStr.data(using: .utf8) else { return [] }

        struct RawFinding: Decodable {
            let name: String
            let type: String
            let description: String
            let url: String?
            let installable: Bool?
        }

        guard let raw = try? JSONDecoder().decode([RawFinding].self, from: data) else { return [] }

        return raw.map { r in
            let findingType: FindingType
            switch r.type.lowercased().replacingOccurrences(of: "_", with: "") {
            case "mcpserver", "mcp": findingType = .mcpServer
            case "api":              findingType = .api
            case "zapier", "make":   findingType = .zapier
            case "native":           findingType = .native
            default:                 findingType = .workaround
            }

            return Finding(
                name: r.name,
                type: findingType,
                description: r.description,
                url: r.url,
                installable: r.installable ?? false
            )
        }
    }

    private func inferActions(from finding: Finding) -> [String] {
        var actions: [String] = []
        let lower = finding.description.lowercased()

        if lower.contains("read") || lower.contains("fetch") || lower.contains("get") { actions.append("read") }
        if lower.contains("write") || lower.contains("create") || lower.contains("post") { actions.append("write") }
        if lower.contains("sync") || lower.contains("transfer") { actions.append("sync") }
        if lower.contains("export") { actions.append("export") }
        if lower.contains("import") { actions.append("import") }
        if lower.contains("search") { actions.append("search") }

        if actions.isEmpty { actions.append("interact") }
        return actions
    }
}
