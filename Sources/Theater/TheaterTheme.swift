import SwiftUI

// MARK: - Theater Color Tokens

/// Color tokens used by theater components. Mirrors the subset of the main app's Theme
/// that theater needs, so the module has no dependency on AutoclawTheme.
public struct TheaterColors {
    public let colorScheme: ColorScheme

    public init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    public var card: Color {
        colorScheme == .dark ? Color(red: 0.118, green: 0.118, blue: 0.118) : .white
    }
    public var textPrimary: Color {
        colorScheme == .dark ? Color(red: 0.941, green: 0.941, blue: 0.941) : Color(red: 0.102, green: 0.102, blue: 0.102)
    }
    public var textMuted: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.4, blue: 0.4) : Color(red: 0.69, green: 0.69, blue: 0.69)
    }
    public var border: Color {
        colorScheme == .dark ? Color(red: 0.165, green: 0.165, blue: 0.165) : Color(red: 0.91, green: 0.91, blue: 0.91)
    }

    // Accent colors
    public static let teal = Color(red: 0.051, green: 0.58, blue: 0.533)
    public static let purple = Color(red: 0.486, green: 0.227, blue: 0.929)
}

// MARK: - Intelligence Glow

public enum GlowState {
    case off, enabled, thinking
}

private struct EnabledGlow: View {
    let color: Color; let cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color.opacity(0.3), lineWidth: 1)
            .allowsHitTesting(false)
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

public extension View {
    func theaterGlow(color: Color, cornerRadius: CGFloat = 20, state: GlowState) -> some View {
        modifier(GlowMod(color: color, cornerRadius: cornerRadius, glowState: state))
    }
}

// MARK: - Color Hex Init

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
