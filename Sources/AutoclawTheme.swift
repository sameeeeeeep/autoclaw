import SwiftUI

// MARK: - Autoclaw Theme

/// Centralized design tokens for the Autoclaw UI.
/// Adapts automatically to light/dark mode via `colorScheme`.
struct Theme {
    let colorScheme: ColorScheme

    // MARK: - Backgrounds

    var page: Color {
        colorScheme == .dark ? Color(hex: 0x111111) : Color(hex: 0xFAFAF8)
    }
    var sidebar: Color {
        colorScheme == .dark ? Color(hex: 0x1A1A1A) : .white
    }
    var card: Color {
        colorScheme == .dark ? Color(hex: 0x1E1E1E) : .white
    }
    var surface: Color {
        colorScheme == .dark ? Color(hex: 0x252525) : Color(hex: 0xF5F5F0)
    }

    // MARK: - Text

    var textPrimary: Color {
        colorScheme == .dark ? Color(hex: 0xF0F0F0) : Color(hex: 0x1A1A1A)
    }
    var textSecondary: Color {
        colorScheme == .dark ? Color(hex: 0x888888) : Color(hex: 0x7A7A7A)
    }
    var textMuted: Color {
        colorScheme == .dark ? Color(hex: 0x666666) : Color(hex: 0xB0B0B0)
    }

    // MARK: - Borders

    var border: Color {
        colorScheme == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE8E8E8)
    }

    // MARK: - Status Colors

    static let blue = Color(hex: 0x2563EB)
    static let green = Color(hex: 0x16A34A)
    static let red = Color(hex: 0xDC2626)
    static let amber = Color(hex: 0xF59E0B)
    static let purple = Color(hex: 0x7C3AED)
    static let pink = Color(hex: 0xDB2777)
    static let indigo = Color(hex: 0x4F46E5)
    static let teal = Color(hex: 0x0D9488)

    // MARK: - Button

    var buttonBg: Color {
        colorScheme == .dark ? .white : Color(hex: 0x1A1A1A)
    }
    var buttonText: Color {
        colorScheme == .dark ? Color(hex: 0x111111) : .white
    }
    var buttonSecondaryBg: Color { card }
    var buttonSecondaryText: Color { textSecondary }
}

// MARK: - WorkflowState Colors

extension Theme {
    func borderColor(for state: WorkflowState) -> Color {
        switch state {
        case .ready:     return border
        case .running:   return Self.blue
        case .completed: return Self.green
        case .failed:    return Self.red
        case .paused:    return border
        }
    }

    func badgeBackground(for state: WorkflowState) -> Color {
        switch state {
        case .ready:     return surface
        case .running:   return Self.blue.opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .completed: return Self.green.opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .failed:    return Self.red.opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .paused:    return surface
        }
    }

    func badgeText(for state: WorkflowState) -> Color {
        switch state {
        case .ready:     return textSecondary
        case .running:   return Self.blue
        case .completed: return Self.green
        case .failed:    return Self.red
        case .paused:    return textMuted
        }
    }

    func glowColor(for state: WorkflowState) -> Color {
        switch state {
        case .running:   return Self.blue.opacity(0.1)
        case .completed: return Self.green.opacity(0.1)
        case .failed:    return Self.red.opacity(0.1)
        default:         return .clear
        }
    }
}

// MARK: - App Icon Mapping

struct AppIconStyle {
    let background: Color
    let foreground: Color
    let systemImage: String
}

extension Theme {
    static func appIcon(for appName: String) -> AppIconStyle {
        let name = appName.lowercased()
        if name.contains("mail") || name.contains("gmail") || name.contains("outlook") {
            return AppIconStyle(background: Color(hex: 0xFEE2E2), foreground: Color(hex: 0xDC2626), systemImage: "envelope.fill")
        }
        if name.contains("sheet") || name.contains("excel") || name.contains("numbers") || name.contains("csv") {
            return AppIconStyle(background: Color(hex: 0xDCFCE7), foreground: Color(hex: 0x16A34A), systemImage: "tablecells.fill")
        }
        if name.contains("calendar") || name.contains("cal") {
            return AppIconStyle(background: Color(hex: 0xDBEAFE), foreground: Color(hex: 0x2563EB), systemImage: "calendar")
        }
        if name.contains("slack") || name.contains("teams") || name.contains("discord") {
            return AppIconStyle(background: Color(hex: 0xFEF3C7), foreground: Color(hex: 0xD97706), systemImage: "bubble.left.and.bubble.right.fill")
        }
        if name.contains("notion") || name.contains("docs") || name.contains("word") || name.contains("document") {
            return AppIconStyle(background: Color(hex: 0xFCE7F3), foreground: Color(hex: 0xDB2777), systemImage: "doc.text.fill")
        }
        if name.contains("chrome") || name.contains("safari") || name.contains("firefox") || name.contains("browser") || name.contains("web") {
            return AppIconStyle(background: Color(hex: 0xE0E7FF), foreground: Color(hex: 0x4F46E5), systemImage: "globe")
        }
        if name.contains("map") || name.contains("location") {
            return AppIconStyle(background: Color(hex: 0xDCFCE7), foreground: Color(hex: 0x16A34A), systemImage: "mappin.circle.fill")
        }
        if name.contains("search") || name.contains("google") {
            return AppIconStyle(background: Color(hex: 0xFEE2E2), foreground: Color(hex: 0xDC2626), systemImage: "magnifyingglass")
        }
        if name.contains("zoom") || name.contains("meet") || name.contains("video") {
            return AppIconStyle(background: Color(hex: 0xE0E7FF), foreground: Color(hex: 0x4F46E5), systemImage: "video.fill")
        }
        if name.contains("figma") || name.contains("sketch") || name.contains("design") {
            return AppIconStyle(background: Color(hex: 0xF3E8FF), foreground: Color(hex: 0x7C3AED), systemImage: "paintbrush.fill")
        }
        if name.contains("clickup") || name.contains("jira") || name.contains("linear") || name.contains("task") {
            return AppIconStyle(background: Color(hex: 0xFEF3C7), foreground: Color(hex: 0xD97706), systemImage: "checkmark.square.fill")
        }
        if name.contains("terminal") || name.contains("code") || name.contains("xcode") {
            return AppIconStyle(background: Color(hex: 0xF5F5F0), foreground: Color(hex: 0x7A7A7A), systemImage: "terminal.fill")
        }
        // Default
        return AppIconStyle(background: Color(hex: 0xF5F5F0), foreground: Color(hex: 0x7A7A7A), systemImage: "app.fill")
    }
}

// MARK: - Reusable View Components

/// Overlapping app icon circles (Cofia-style)
struct AppIconRow: View {
    let apps: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -(size * 0.2)) {
            ForEach(Array(apps.prefix(4).enumerated()), id: \.offset) { idx, app in
                let style = Theme.appIcon(for: app)
                ZStack {
                    Circle()
                        .fill(style.background)
                        .frame(width: size, height: size)
                    if idx > 0 {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: size, height: size)
                    }
                    Image(systemName: style.systemImage)
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(style.foreground)
                }
            }
        }
    }
}

/// Status badge (READY, RUNNING, COMPLETED, etc.)
struct StatusBadge: View {
    let state: WorkflowState
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme(colorScheme: colorScheme) }

    var body: some View {
        Text(state.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1)
            .foregroundStyle(theme.badgeText(for: state))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.badgeBackground(for: state))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Glow State

enum GlowState: Equatable { case off, enabled, thinking }

// MARK: - Intelligence Glow

private struct EnabledGlow: View {
    let color: Color; let cornerRadius: CGFloat
    @State private var opacity: Double = 0.15
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color.opacity(opacity), lineWidth: 1.5).blur(radius: 3).allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { opacity = 0.40 } }
    }
}

private struct ThinkingGlow: View {
    let color: Color; let cornerRadius: CGFloat
    @State private var stops: [Gradient.Stop]
    init(color: Color, cornerRadius: CGFloat) { self.color = color; self.cornerRadius = cornerRadius; _stops = State(initialValue: Self.makeStops(color: color)) }
    var body: some View {
        let g = AngularGradient(gradient: Gradient(stops: stops), center: .center)
        let s = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            s.strokeBorder(g, lineWidth: 1.5).animation(.easeInOut(duration: 0.90), value: stops)
            s.strokeBorder(g, lineWidth: 3).blur(radius: 2).animation(.easeInOut(duration: 1.15), value: stops)
            s.strokeBorder(g, lineWidth: 5).blur(radius: 4).animation(.easeInOut(duration: 1.45), value: stops)
        }.allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(0.75)); stops = Self.makeStops(color: color) } }
    }
    static func makeStops(color: Color) -> [Gradient.Stop] {
        [color.opacity(0.95), color.opacity(0.20), color.opacity(0.60), color.opacity(0.88), color.opacity(0.16), color.opacity(0.72)]
            .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }.sorted { $0.location < $1.location }
    }
}

private struct GlowMod: ViewModifier {
    let color: Color; let cornerRadius: CGFloat; let glowState: GlowState
    func body(content: Content) -> some View {
        content.overlay {
            switch glowState {
            case .off: EmptyView()
            case .enabled: EnabledGlow(color: color, cornerRadius: cornerRadius)
            case .thinking: ThinkingGlow(color: color, cornerRadius: cornerRadius)
            }
        }
    }
}

extension View {
    func intelligenceGlow(color: Color, cornerRadius: CGFloat = 20, state: GlowState) -> some View {
        modifier(GlowMod(color: color, cornerRadius: cornerRadius, glowState: state))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(proposal: proposal, subviews: subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(proposal: proposal, subviews: subviews)
        for (i, p) in r.positions.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let mw = proposal.width ?? .infinity; var ps: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rh: CGFloat = 0
        for sv in subviews { let s = sv.sizeThatFits(.unspecified); if x + s.width > mw && x > 0 { x = 0; y += rh + spacing; rh = 0 }; ps.append(CGPoint(x: x, y: y)); rh = max(rh, s.height); x += s.width + spacing }
        return (ps, CGSize(width: mw, height: y + rh))
    }
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(colorScheme: .dark)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
