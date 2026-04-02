import Foundation

/// Resolves raw browser URLs into semantic web app identities.
/// "https://www.notion.so/workspace/My-Page-abc123" → (app: "Notion", section: "Page", detail: "My Page")
struct WebAppResolver {

    struct ResolvedApp: Equatable {
        let appName: String       // "Notion", "Figma", "Google Sheets", etc.
        let category: AppCategory // productivity, design, communication, etc.
        let section: String?      // "Database", "Inbox", "Editor", "Search", etc.
        let detail: String?       // page name, doc title, or nil

        var displayName: String {
            if let section = section {
                return "\(appName) (\(section))"
            }
            return appName
        }
    }

    enum AppCategory: String, Codable {
        case productivity   // Notion, Google Docs, Airtable
        case design         // Figma, Canva, Freepik
        case communication  // Slack, Gmail, Discord, LinkedIn
        case development    // GitHub, Linear, Vercel
        case analytics      // Google Analytics, Mixpanel
        case media          // YouTube, Spotify
        case search         // Google Search, Perplexity
        case storage        // Google Drive, Dropbox
        case finance        // Stripe, QuickBooks
        case other
    }

    /// Resolve a full URL to a web app identity. Returns nil if the domain isn't recognized.
    static func resolve(url: String) -> ResolvedApp? {
        guard let parsed = URL(string: url),
              let host = parsed.host?.lowercased() else { return nil }

        let path = parsed.path.lowercased()
        let cleanHost = host.replacingOccurrences(of: "www.", with: "")

        // Try exact domain match first, then suffix match
        for (pattern, resolver) in domainResolvers {
            if cleanHost == pattern || cleanHost.hasSuffix("." + pattern) {
                return resolver(cleanHost, path, parsed)
            }
        }

        // Fallback: extract a readable name from the domain
        return fallbackResolve(host: cleanHost, path: path)
    }

    /// Extract just the app name from a URL (convenience for quick lookups)
    static func appName(for url: String) -> String? {
        resolve(url: url)?.appName
    }

    /// Check if a URL belongs to a known web app
    static func isKnownApp(_ url: String) -> Bool {
        resolve(url: url) != nil
    }

    // MARK: - Domain Resolvers

    private typealias Resolver = (String, String, URL) -> ResolvedApp

    private static let domainResolvers: [(String, Resolver)] = [
        // Productivity
        ("notion.so", resolveNotion),
        ("notion.site", resolveNotion),
        ("docs.google.com", resolveGoogleDocs),
        ("sheets.google.com", resolveGoogleSheets),
        ("slides.google.com", resolveGoogleSlides),
        ("airtable.com", { _, p, _ in ResolvedApp(appName: "Airtable", category: .productivity, section: sectionFromPath(p, patterns: airtableSections), detail: nil) }),
        ("clickup.com", { _, p, _ in ResolvedApp(appName: "ClickUp", category: .productivity, section: sectionFromPath(p, patterns: clickupSections), detail: nil) }),
        ("linear.app", { _, p, _ in ResolvedApp(appName: "Linear", category: .development, section: sectionFromPath(p, patterns: linearSections), detail: nil) }),
        ("asana.com", { _, p, _ in ResolvedApp(appName: "Asana", category: .productivity, section: nil, detail: nil) }),
        ("monday.com", { _, p, _ in ResolvedApp(appName: "Monday", category: .productivity, section: nil, detail: nil) }),
        ("trello.com", { _, p, _ in ResolvedApp(appName: "Trello", category: .productivity, section: nil, detail: nil) }),
        ("coda.io", { _, _, _ in ResolvedApp(appName: "Coda", category: .productivity, section: nil, detail: nil) }),

        // Design
        ("figma.com", resolveFigma),
        ("canva.com", { _, p, _ in ResolvedApp(appName: "Canva", category: .design, section: sectionFromPath(p, patterns: canvaSections), detail: nil) }),
        ("freepik.com", { _, p, _ in ResolvedApp(appName: "Freepik", category: .design, section: sectionFromPath(p, patterns: freepikSections), detail: nil) }),
        ("dribbble.com", { _, _, _ in ResolvedApp(appName: "Dribbble", category: .design, section: nil, detail: nil) }),
        ("behance.net", { _, _, _ in ResolvedApp(appName: "Behance", category: .design, section: nil, detail: nil) }),
        ("miro.com", { _, _, _ in ResolvedApp(appName: "Miro", category: .design, section: nil, detail: nil) }),

        // Communication
        ("mail.google.com", resolveGmail),
        ("slack.com", { _, p, _ in ResolvedApp(appName: "Slack", category: .communication, section: nil, detail: nil) }),
        ("app.slack.com", { _, p, _ in ResolvedApp(appName: "Slack", category: .communication, section: nil, detail: nil) }),
        ("discord.com", { _, _, _ in ResolvedApp(appName: "Discord", category: .communication, section: nil, detail: nil) }),
        ("linkedin.com", { _, p, _ in ResolvedApp(appName: "LinkedIn", category: .communication, section: sectionFromPath(p, patterns: linkedinSections), detail: nil) }),
        ("twitter.com", { _, _, _ in ResolvedApp(appName: "Twitter/X", category: .communication, section: nil, detail: nil) }),
        ("x.com", { _, _, _ in ResolvedApp(appName: "Twitter/X", category: .communication, section: nil, detail: nil) }),
        ("teams.microsoft.com", { _, _, _ in ResolvedApp(appName: "Microsoft Teams", category: .communication, section: nil, detail: nil) }),
        ("outlook.live.com", { _, _, _ in ResolvedApp(appName: "Outlook", category: .communication, section: nil, detail: nil) }),
        ("outlook.office.com", { _, _, _ in ResolvedApp(appName: "Outlook", category: .communication, section: nil, detail: nil) }),
        ("calendar.google.com", { _, _, _ in ResolvedApp(appName: "Google Calendar", category: .productivity, section: nil, detail: nil) }),
        ("meet.google.com", { _, _, _ in ResolvedApp(appName: "Google Meet", category: .communication, section: nil, detail: nil) }),
        ("zoom.us", { _, _, _ in ResolvedApp(appName: "Zoom", category: .communication, section: nil, detail: nil) }),

        // Development
        ("github.com", resolveGitHub),
        ("gitlab.com", { _, _, _ in ResolvedApp(appName: "GitLab", category: .development, section: nil, detail: nil) }),
        ("vercel.com", { _, _, _ in ResolvedApp(appName: "Vercel", category: .development, section: nil, detail: nil) }),
        ("netlify.com", { _, _, _ in ResolvedApp(appName: "Netlify", category: .development, section: nil, detail: nil) }),
        ("railway.app", { _, _, _ in ResolvedApp(appName: "Railway", category: .development, section: nil, detail: nil) }),
        ("supabase.com", { _, _, _ in ResolvedApp(appName: "Supabase", category: .development, section: nil, detail: nil) }),
        ("firebase.google.com", { _, _, _ in ResolvedApp(appName: "Firebase", category: .development, section: nil, detail: nil) }),
        ("console.cloud.google.com", { _, _, _ in ResolvedApp(appName: "Google Cloud", category: .development, section: nil, detail: nil) }),
        ("aws.amazon.com", { _, _, _ in ResolvedApp(appName: "AWS", category: .development, section: nil, detail: nil) }),
        ("console.anthropic.com", { _, _, _ in ResolvedApp(appName: "Anthropic Console", category: .development, section: nil, detail: nil) }),
        ("platform.openai.com", { _, _, _ in ResolvedApp(appName: "OpenAI Platform", category: .development, section: nil, detail: nil) }),

        // Analytics
        ("analytics.google.com", { _, _, _ in ResolvedApp(appName: "Google Analytics", category: .analytics, section: nil, detail: nil) }),
        ("mixpanel.com", { _, _, _ in ResolvedApp(appName: "Mixpanel", category: .analytics, section: nil, detail: nil) }),
        ("amplitude.com", { _, _, _ in ResolvedApp(appName: "Amplitude", category: .analytics, section: nil, detail: nil) }),

        // Storage
        ("drive.google.com", { _, _, _ in ResolvedApp(appName: "Google Drive", category: .storage, section: nil, detail: nil) }),
        ("dropbox.com", { _, _, _ in ResolvedApp(appName: "Dropbox", category: .storage, section: nil, detail: nil) }),
        ("onedrive.live.com", { _, _, _ in ResolvedApp(appName: "OneDrive", category: .storage, section: nil, detail: nil) }),

        // Media
        ("youtube.com", { _, p, _ in ResolvedApp(appName: "YouTube", category: .media, section: p.contains("/watch") ? "Video" : nil, detail: nil) }),
        ("spotify.com", { _, _, _ in ResolvedApp(appName: "Spotify", category: .media, section: nil, detail: nil) }),

        // Search
        ("google.com", resolveGoogle),
        ("perplexity.ai", { _, _, _ in ResolvedApp(appName: "Perplexity", category: .search, section: nil, detail: nil) }),
        ("bing.com", { _, _, _ in ResolvedApp(appName: "Bing", category: .search, section: nil, detail: nil) }),
        ("claude.ai", { _, p, _ in
            if p.contains("/code") {
                return ResolvedApp(appName: "Claude Code", category: .development, section: "Code", detail: nil)
            } else if p.contains("/cowork") {
                return ResolvedApp(appName: "Claude Cowork", category: .development, section: "Cowork", detail: nil)
            } else {
                return ResolvedApp(appName: "Claude", category: .search, section: nil, detail: nil)
            }
        }),
        ("chatgpt.com", { _, _, _ in ResolvedApp(appName: "ChatGPT", category: .search, section: nil, detail: nil) }),
        ("chat.openai.com", { _, _, _ in ResolvedApp(appName: "ChatGPT", category: .search, section: nil, detail: nil) }),

        // Finance
        ("dashboard.stripe.com", { _, _, _ in ResolvedApp(appName: "Stripe", category: .finance, section: nil, detail: nil) }),
        ("app.qbo.intuit.com", { _, _, _ in ResolvedApp(appName: "QuickBooks", category: .finance, section: nil, detail: nil) }),

        // AI / Tools
        ("huggingface.co", { _, _, _ in ResolvedApp(appName: "Hugging Face", category: .development, section: nil, detail: nil) }),
        ("replicate.com", { _, _, _ in ResolvedApp(appName: "Replicate", category: .development, section: nil, detail: nil) }),
    ]

    // MARK: - Specific Resolvers

    private static func resolveNotion(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        // Notion paths: /workspace/Page-Name-uuid or /database-uuid
        var section: String? = nil
        if path.contains("/database") || path.contains("?v=") {
            section = "Database"
        } else if path.count > 2 {
            section = "Page"
        }
        return ResolvedApp(appName: "Notion", category: .productivity, section: section, detail: nil)
    }

    private static func resolveGoogleDocs(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        let section: String?
        if path.contains("/edit") { section = "Editor" }
        else if path.contains("/preview") { section = "Preview" }
        else { section = nil }
        return ResolvedApp(appName: "Google Docs", category: .productivity, section: section, detail: nil)
    }

    private static func resolveGoogleSheets(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        return ResolvedApp(appName: "Google Sheets", category: .productivity, section: path.contains("/edit") ? "Editor" : nil, detail: nil)
    }

    private static func resolveGoogleSlides(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        return ResolvedApp(appName: "Google Slides", category: .productivity, section: path.contains("/edit") ? "Editor" : nil, detail: nil)
    }

    private static func resolveGmail(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        let section: String?
        if path.contains("/compose") || url.absoluteString.contains("#compose") { section = "Compose" }
        else if path.contains("/inbox") || url.absoluteString.contains("#inbox") { section = "Inbox" }
        else if path.contains("/sent") || url.absoluteString.contains("#sent") { section = "Sent" }
        else if path.contains("/search") || url.absoluteString.contains("#search") { section = "Search" }
        else { section = nil }
        return ResolvedApp(appName: "Gmail", category: .communication, section: section, detail: nil)
    }

    private static func resolveFigma(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        let section: String?
        if path.contains("/design/") || path.contains("/file/") { section = "Editor" }
        else if path.contains("/proto") { section = "Prototype" }
        else if path.contains("/board") { section = "FigJam" }
        else if path.contains("/team/") || path.contains("/files") { section = "Files" }
        else { section = nil }
        return ResolvedApp(appName: "Figma", category: .design, section: section, detail: nil)
    }

    private static func resolveGitHub(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        let parts = path.split(separator: "/").map(String.init)
        let section: String?
        if parts.count >= 3 {
            let sub = parts[2]
            switch sub {
            case "issues":    section = "Issues"
            case "pull":      section = "Pull Requests"
            case "actions":   section = "Actions"
            case "settings":  section = "Settings"
            case "tree", "blob": section = "Code"
            default:          section = nil
            }
        } else {
            section = path.contains("/notifications") ? "Notifications" : nil
        }
        let detail = parts.count >= 2 ? "\(parts[0])/\(parts[1])" : nil
        return ResolvedApp(appName: "GitHub", category: .development, section: section, detail: detail)
    }

    private static func resolveGoogle(_ host: String, _ path: String, _ url: URL) -> ResolvedApp {
        if path.hasPrefix("/search") || path.hasPrefix("/webhp") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value
            return ResolvedApp(appName: "Google Search", category: .search, section: nil, detail: query)
        }
        if path.hasPrefix("/maps") {
            return ResolvedApp(appName: "Google Maps", category: .other, section: nil, detail: nil)
        }
        return ResolvedApp(appName: "Google", category: .search, section: nil, detail: nil)
    }

    // MARK: - Section Pattern Matching

    private static func sectionFromPath(_ path: String, patterns: [(String, String)]) -> String? {
        for (pattern, section) in patterns {
            if path.contains(pattern) { return section }
        }
        return nil
    }

    private static let airtableSections: [(String, String)] = [
        ("/tbl", "Table"), ("/viw", "View"), ("/form", "Form"),
    ]

    private static let clickupSections: [(String, String)] = [
        ("/board", "Board"), ("/list", "List"), ("/gantt", "Gantt"),
        ("/calendar", "Calendar"), ("/docs", "Docs"),
    ]

    private static let linearSections: [(String, String)] = [
        ("/issue", "Issue"), ("/project", "Project"), ("/cycle", "Cycle"),
        ("/inbox", "Inbox"), ("/settings", "Settings"),
    ]

    private static let canvaSections: [(String, String)] = [
        ("/design", "Editor"), ("/folder", "Folder"), ("/templates", "Templates"),
    ]

    private static let freepikSections: [(String, String)] = [
        ("/search", "Search"), ("/pikaso", "AI Generator"), ("/projects", "Projects"),
        ("/collection", "Collection"),
    ]

    private static let linkedinSections: [(String, String)] = [
        ("/messaging", "Messages"), ("/feed", "Feed"), ("/jobs", "Jobs"),
        ("/mynetwork", "Network"), ("/in/", "Profile"),
    ]

    // MARK: - Fallback

    /// For unrecognized domains, extract a readable name from the hostname
    private static func fallbackResolve(host: String, path: String) -> ResolvedApp? {
        let clean = host.replacingOccurrences(of: "www.", with: "")

        // Skip localhost, IPs, internal domains
        if clean.hasPrefix("localhost") || clean.hasPrefix("127.") || clean.hasPrefix("192.168") { return nil }
        if clean.hasSuffix(".local") { return nil }

        // Extract the main domain name and capitalize it
        let parts = clean.split(separator: ".")
        guard let name = parts.first, parts.count >= 2 else { return nil }

        let capitalized = String(name).prefix(1).uppercased() + String(name).dropFirst()
        return ResolvedApp(appName: capitalized, category: .other, section: nil, detail: nil)
    }
}
