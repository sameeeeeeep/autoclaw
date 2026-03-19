import Foundation

/// Indexes everything autoclaw can do — installed MCP tools, known APIs, available automations.
/// The FrictionDetector matches observed user activity against these capabilities to find
/// moments where AI could help.
@MainActor
final class CapabilityMap: ObservableObject {

    // MARK: - Types

    struct Capability: Identifiable, Codable {
        let id: UUID
        let name: String               // "Read Notion pages", "Send Slack message"
        let provider: String            // "MCP: clickup", "API: Google Sheets", "Claude Code"
        let sourceApp: String           // which app this capability relates to
        let targetApp: String?          // if it bridges two apps
        let actions: [String]           // verbs: "read", "write", "sync", "export", "send"
        let description: String
        let isInstalled: Bool           // true if MCP/tool is installed, false if discovered online
        let discoveredFrom: String?     // URL or search query that found this
        let addedAt: Date

        init(
            name: String,
            provider: String,
            sourceApp: String,
            targetApp: String? = nil,
            actions: [String],
            description: String,
            isInstalled: Bool = true,
            discoveredFrom: String? = nil
        ) {
            self.id = UUID()
            self.name = name
            self.provider = provider
            self.sourceApp = sourceApp
            self.targetApp = targetApp
            self.actions = actions
            self.description = description
            self.isInstalled = isInstalled
            self.discoveredFrom = discoveredFrom
            self.addedAt = Date()
        }
    }

    /// A match between observed friction and a capability that could resolve it
    struct CapabilityMatch {
        let capability: Capability
        let friction: String            // what the user is doing manually
        let confidence: Double          // 0-1 how well this matches
        let suggestion: String          // human-readable offer
    }

    // MARK: - State

    @Published var capabilities: [Capability] = []
    @Published var lastScannedAt: Date?

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Autoclaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("capabilities.json")
        load()
    }

    // MARK: - Scan Installed MCP Tools

    /// Scan Claude Code's MCP configuration to discover available tools
    func scanInstalledTools() {
        var discovered: [Capability] = []

        let home = NSHomeDirectory()

        // 1. Read ~/.claude/mcp.json (MCP server definitions)
        let mcpJsonPath = home + "/.claude/mcp.json"
        if let mcpCaps = scanMCPJson(at: mcpJsonPath) {
            discovered.append(contentsOf: mcpCaps)
        }

        // 2. Read ~/.claude/settings.json for permission patterns (mcp__serverName__*)
        //    and enabledMcpjsonServers list
        let claudeSettingsPath = home + "/.claude/settings.json"
        let localSettingsPath = home + "/.claude/settings.local.json"

        for path in [claudeSettingsPath, localSettingsPath] {
            if let caps = scanClaudeSettings(at: path) {
                discovered.append(contentsOf: caps)
            }
        }

        // 3. Read project-level MCP settings
        let projectSettingsPattern = home + "/.claude/projects"
        if let projectCaps = scanProjectSettings(at: projectSettingsPattern) {
            discovered.append(contentsOf: projectCaps)
        }

        // Add built-in capabilities (things Claude Code can always do)
        discovered.append(contentsOf: builtInCapabilities)

        // Merge with existing (don't duplicate)
        let existingProviders = Set(capabilities.map { $0.provider + ":" + $0.name })
        for cap in discovered {
            let key = cap.provider + ":" + cap.name
            if !existingProviders.contains(key) {
                capabilities.append(cap)
            }
        }

        lastScannedAt = Date()
        persist()

        DebugLog.log("[CapabilityMap] Scanned: \(capabilities.count) capabilities (\(discovered.count) from MCP scan)")
    }

    // MARK: - Query

    /// Find capabilities that could handle work involving a specific app
    func capabilities(for appName: String) -> [Capability] {
        let lower = appName.lowercased()
        return capabilities.filter {
            $0.sourceApp.lowercased() == lower ||
            $0.targetApp?.lowercased() == lower ||
            $0.name.lowercased().contains(lower)
        }
    }

    /// Find capabilities that bridge two specific apps
    func capabilities(from sourceApp: String, to targetApp: String) -> [Capability] {
        let srcLower = sourceApp.lowercased()
        let tgtLower = targetApp.lowercased()
        return capabilities.filter { cap in
            (cap.sourceApp.lowercased() == srcLower && cap.targetApp?.lowercased() == tgtLower) ||
            (cap.sourceApp.lowercased() == tgtLower && cap.targetApp?.lowercased() == srcLower) ||
            (cap.actions.contains("sync") && (cap.sourceApp.lowercased() == srcLower || cap.sourceApp.lowercased() == tgtLower))
        }
    }

    /// Find capabilities that can perform a specific action on an app
    func capabilities(action: String, app: String) -> [Capability] {
        let appLower = app.lowercased()
        let actionLower = action.lowercased()
        return capabilities.filter {
            $0.actions.contains(actionLower) &&
            ($0.sourceApp.lowercased() == appLower || $0.targetApp?.lowercased() == appLower)
        }
    }

    /// Check if we have ANY capability for an app
    func hasCapability(for appName: String) -> Bool {
        !capabilities(for: appName).isEmpty
    }

    /// All apps we have capabilities for
    var supportedApps: Set<String> {
        var apps = Set<String>()
        for cap in capabilities {
            apps.insert(cap.sourceApp)
            if let target = cap.targetApp { apps.insert(target) }
        }
        return apps
    }

    /// Add a capability discovered from web search
    func addDiscovered(_ capability: Capability) {
        capabilities.append(capability)
        persist()
    }

    // MARK: - MCP Settings Scanner

    /// Scan ~/.claude/mcp.json for server definitions
    private func scanMCPJson(at path: String) -> [Capability]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else { return nil }

        var caps: [Capability] = []
        for (serverName, _) in mcpServers {
            caps.append(contentsOf: capabilitiesFromMCPServer(name: serverName))
        }
        return caps.isEmpty ? nil : caps
    }

    private func scanClaudeSettings(at path: String) -> [Capability]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Look for mcpServers in the settings
        guard let mcpServers = json["mcpServers"] as? [String: Any] else {
            // Also check permissions.allow for MCP tool patterns
            return parseMCPFromPermissions(json)
        }

        var caps: [Capability] = []

        for (serverName, _) in mcpServers {
            let serverCaps = capabilitiesFromMCPServer(name: serverName)
            caps.append(contentsOf: serverCaps)
        }

        return caps
    }

    private func parseMCPFromPermissions(_ json: [String: Any]) -> [Capability]? {
        guard let permissions = json["permissions"] as? [String: Any],
              let allow = permissions["allow"] as? [String] else { return nil }

        var caps: [Capability] = []
        var seenServers = Set<String>()

        for pattern in allow {
            // MCP tool patterns look like "mcp__serverName__toolName"
            if pattern.hasPrefix("mcp__") {
                let parts = pattern.split(separator: "_").filter { !$0.isEmpty }
                // Pattern: mcp, <serverId>, <toolName>
                // The server name is typically the readable part
                if parts.count >= 3 {
                    let serverPart = String(parts[1])
                    if !seenServers.contains(serverPart) {
                        seenServers.insert(serverPart)
                        let serverCaps = capabilitiesFromMCPServer(name: serverPart)
                        caps.append(contentsOf: serverCaps)
                    }
                }
            }
        }

        return caps.isEmpty ? nil : caps
    }

    private func scanProjectSettings(at basePath: String) -> [Capability]? {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: basePath) else { return nil }

        var caps: [Capability] = []
        for project in projects {
            let settingsPath = (basePath as NSString).appendingPathComponent(project + "/settings.local.json")
            if let projectCaps = scanClaudeSettings(at: settingsPath) {
                caps.append(contentsOf: projectCaps)
            }
        }
        return caps.isEmpty ? nil : caps
    }

    // MARK: - MCP Server → Capabilities Mapping

    /// Map known MCP server names to their capabilities
    private func capabilitiesFromMCPServer(name: String) -> [Capability] {
        let lower = name.lowercased()

        // Known MCP servers and what they can do
        if lower.contains("clickup") {
            return [
                Capability(name: "Read ClickUp tasks", provider: "MCP: \(name)", sourceApp: "ClickUp", actions: ["read", "search", "filter"], description: "Read, search, and filter tasks in ClickUp"),
                Capability(name: "Create/update ClickUp tasks", provider: "MCP: \(name)", sourceApp: "ClickUp", actions: ["write", "create", "update"], description: "Create and update tasks, comments, time entries in ClickUp"),
                Capability(name: "Manage ClickUp workspace", provider: "MCP: \(name)", sourceApp: "ClickUp", actions: ["read", "organize"], description: "Manage folders, lists, documents in ClickUp"),
            ]
        }
        if lower.contains("slack") {
            return [
                Capability(name: "Send Slack messages", provider: "MCP: \(name)", sourceApp: "Slack", actions: ["send", "write"], description: "Send messages to Slack channels"),
                Capability(name: "Read Slack messages", provider: "MCP: \(name)", sourceApp: "Slack", actions: ["read", "search"], description: "Read and search Slack messages"),
            ]
        }
        if lower.contains("notion") {
            return [
                Capability(name: "Read Notion pages", provider: "MCP: \(name)", sourceApp: "Notion", actions: ["read", "search"], description: "Read and search Notion pages and databases"),
                Capability(name: "Write to Notion", provider: "MCP: \(name)", sourceApp: "Notion", actions: ["write", "create", "update"], description: "Create and update Notion pages and database entries"),
            ]
        }
        if lower.contains("github") {
            return [
                Capability(name: "Manage GitHub repos", provider: "MCP: \(name)", sourceApp: "GitHub", actions: ["read", "write", "create"], description: "Manage issues, PRs, code on GitHub"),
            ]
        }
        if lower.contains("linear") {
            return [
                Capability(name: "Manage Linear issues", provider: "MCP: \(name)", sourceApp: "Linear", actions: ["read", "write", "create"], description: "Create and manage Linear issues and projects"),
            ]
        }
        if lower.contains("google") && lower.contains("sheet") {
            return [
                Capability(name: "Read/write Google Sheets", provider: "MCP: \(name)", sourceApp: "Google Sheets", actions: ["read", "write", "create"], description: "Read, write, and create Google Sheets spreadsheets"),
            ]
        }
        if lower.contains("figma") {
            return [
                Capability(name: "Read Figma designs", provider: "MCP: \(name)", sourceApp: "Figma", actions: ["read", "inspect", "export"], description: "Read design files, inspect components, export assets from Figma"),
            ]
        }
        if lower.contains("chrome") || lower.contains("browser") {
            return [
                Capability(name: "Control browser", provider: "MCP: \(name)", sourceApp: "Chrome", actions: ["navigate", "read", "interact", "screenshot"], description: "Navigate pages, read content, interact with web apps, take screenshots"),
            ]
        }
        if lower.contains("granola") || lower.contains("meeting") {
            return [
                Capability(name: "Access meeting transcripts", provider: "MCP: \(name)", sourceApp: "Meetings", actions: ["read", "search", "transcribe"], description: "Read meeting transcripts and notes"),
            ]
        }
        if lower.contains("desktop") || lower.contains("commander") {
            return [
                Capability(name: "Control desktop", provider: "MCP: \(name)", sourceApp: "macOS", actions: ["read", "write", "execute", "search"], description: "Read/write files, run commands, manage processes on macOS"),
            ]
        }

        // Unknown MCP server — add a generic capability
        return [
            Capability(name: "MCP: \(name)", provider: "MCP: \(name)", sourceApp: name, actions: ["interact"], description: "MCP server: \(name) (capabilities unknown — will be discovered on use)"),
        ]
    }

    // MARK: - Built-in Capabilities

    private var builtInCapabilities: [Capability] {
        [
            Capability(name: "Read and write files", provider: "Claude Code", sourceApp: "File System", actions: ["read", "write", "search", "create"], description: "Read, write, search, and create files on the local file system"),
            Capability(name: "Run shell commands", provider: "Claude Code", sourceApp: "Terminal", actions: ["execute", "build", "test"], description: "Execute shell commands, run builds and tests"),
            Capability(name: "Web search", provider: "Claude Code", sourceApp: "Web", actions: ["search", "fetch"], description: "Search the web and fetch page content"),
            Capability(name: "Generate code", provider: "Claude Code", sourceApp: "Code", actions: ["write", "refactor", "explain"], description: "Write, refactor, and explain code in any language"),
            Capability(name: "Process documents", provider: "Claude Code", sourceApp: "Documents", actions: ["read", "create", "convert"], description: "Read PDFs, create Word docs, process spreadsheets"),
        ]
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Capability].self, from: data) else { return }
        capabilities = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(capabilities) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
