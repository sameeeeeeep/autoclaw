import SwiftUI

// MARK: - Theater Scene Backgrounds

/// Renders a themed background scene for each of the 8 dialog themes.
/// Pixel-art-inspired style with gradients and geometric shapes.
/// Supports scene location changes and ambient dynamics.
struct TheaterSceneBackground: View {
    let themeId: String
    let animTick: Int
    /// Whether a character is currently speaking — drives ambient intensity
    var isSpeaking: Bool = false
    /// Which character is speaking (nil = nobody) — drives directional lighting
    var speakingChar: Int = 0 // 0 = none, 1 = char1 (left), 2 = char2 (right)
    /// Scene variant — cycles through locations within each theme (0, 1, 2)
    var sceneVariant: Int = 0

    /// Ambient lighting phase — slow sine wave for environmental mood shifts
    private var ambientPhase: Double { Double(animTick) * 0.04 }
    /// Faster pulse when characters are speaking
    private var speakPulse: Double { isSpeaking ? sin(Double(animTick) * 0.3) * 0.15 : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                scene(for: themeId, variant: sceneVariant, size: geo.size)

                // Ambient lighting overlay — directional glow toward speaker
                if isSpeaking {
                    let leftGlow = speakingChar == 1
                    RadialGradient(
                        colors: [
                            ambientColor(for: themeId).opacity(0.12 + speakPulse * 0.5),
                            .clear
                        ],
                        center: leftGlow ? .leading : .trailing,
                        startRadius: 10,
                        endRadius: geo.size.width * 0.7
                    )
                    .allowsHitTesting(false)
                }

                // Slow ambient breathing — the whole scene subtly shifts brightness
                Rectangle()
                    .fill(.black.opacity(0.03 + sin(ambientPhase) * 0.02))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Theme-specific ambient light color
    private func ambientColor(for id: String) -> Color {
        switch id {
        case "gilfoyle-dinesh":     return Color(hex: 0x00FF44)  // Green terminal glow
        case "david-moira":         return Color(hex: 0xE8A878)  // Warm motel sunset
        case "dwight-jim":          return Color(hex: 0xFFDD66)  // Fluorescent office
        case "chandler-joey":       return Color(hex: 0xFF9944)  // Warm coffee shop
        case "rick-morty":          return Color(hex: 0x44FFAA)  // Portal green
        case "sherlock-watson":     return Color(hex: 0xFF8833)  // Fireplace amber
        case "jesse-walter":        return Color(hex: 0xFFCC00)  // Lab yellow
        case "tony-jarvis":         return Color(hex: 0x44BBFF)  // Arc reactor blue
        default:                    return Color(hex: 0x00FF44)
        }
    }

    @ViewBuilder
    private func scene(for id: String, variant: Int, size: CGSize) -> some View {
        switch id {
        case "gilfoyle-dinesh":
            switch variant % 3 {
            case 1:  siliconValleyRooftopScene(size: size)
            case 2:  siliconValleyGarageScene(size: size)
            default: siliconValleyScene(size: size)
            }
        case "david-moira":
            switch variant % 3 {
            case 1:  schittsCreekCafeScene(size: size)
            case 2:  schittsCreekTownHallScene(size: size)
            default: schittsCreekScene(size: size)
            }
        case "dwight-jim":
            switch variant % 3 {
            case 1:  theOfficeWarehouseScene(size: size)
            case 2:  theOfficeBreakRoomScene(size: size)
            default: theOfficeScene(size: size)
            }
        case "chandler-joey":
            switch variant % 3 {
            case 1:  friendsCentralPerkNightScene(size: size)
            case 2:  friendsRooftopScene(size: size)
            default: friendsScene(size: size)
            }
        case "rick-morty":
            switch variant % 3 {
            case 1:  rickAndMortyAlienPlanetScene(size: size)
            case 2:  rickAndMortySpaceshipScene(size: size)
            default: rickAndMortyScene(size: size)
            }
        case "sherlock-watson":
            switch variant % 3 {
            case 1:  sherlockAlleyScene(size: size)
            case 2:  sherlockMorgueScene(size: size)
            default: sherlockScene(size: size)
            }
        case "jesse-walter":
            switch variant % 3 {
            case 1:  breakingBadDesertScene(size: size)
            case 2:  breakingBadLaundryScene(size: size)
            default: breakingBadScene(size: size)
            }
        case "tony-jarvis":
            switch variant % 3 {
            case 1:  ironManSkyScene(size: size)
            case 2:  ironManAvengersHQScene(size: size)
            default: ironManScene(size: size)
            }
        default: siliconValleyScene(size: size)
        }
    }

    // MARK: - Silicon Valley — Hacker Hostel / Server Room

    private func siliconValleyScene(size: CGSize) -> some View {
        ZStack {
            // Dark blue-gray office
            LinearGradient(
                colors: [Color(hex: 0x1A2030), Color(hex: 0x0E1520)],
                startPoint: .top, endPoint: .bottom
            )

            // Floor
            Rectangle()
                .fill(Color(hex: 0x2A2A35))
                .frame(height: size.height * 0.2)
                .offset(y: size.height * 0.4)

            // Server rack left
            serverRack(x: size.width * 0.1, y: size.height * 0.25, size: size)
            // Server rack right
            serverRack(x: size.width * 0.85, y: size.height * 0.25, size: size)

            // Monitor glow on desk
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x00AA44).opacity(0.6))
                .frame(width: size.width * 0.12, height: size.height * 0.12)
                .offset(x: -size.width * 0.3, y: -size.height * 0.1)

            // Blinking LED lights
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i % 2 == animTick % 2
                          ? Color(hex: 0x00FF44).opacity(0.7)
                          : Color(hex: 0x00FF44).opacity(0.15))
                    .frame(width: 3, height: 3)
                    .offset(
                        x: size.width * 0.1 - size.width / 2 + 8,
                        y: size.height * 0.15 + CGFloat(i) * 8
                    )
            }
        }
    }

    private func serverRack(x: CGFloat, y: CGFloat, size: CGSize) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x3A3A4A))
                    .frame(width: size.width * 0.08, height: 6)
            }
        }
        .offset(x: x - size.width / 2, y: y - size.height / 2)
    }

    // MARK: - Schitt's Creek — Rosebud Motel

    private func schittsCreekScene(size: CGSize) -> some View {
        ZStack {
            // Warm sunset sky
            LinearGradient(
                colors: [Color(hex: 0x5A3060), Color(hex: 0xDA8060), Color(hex: 0xE8A878)],
                startPoint: .top, endPoint: .bottom
            )

            // Motel building
            Rectangle()
                .fill(Color(hex: 0xD8C8A8))
                .frame(width: size.width * 0.8, height: size.height * 0.35)
                .offset(y: size.height * 0.15)

            // Roof
            Rectangle()
                .fill(Color(hex: 0x6A4A3A))
                .frame(width: size.width * 0.85, height: size.height * 0.06)
                .offset(y: -size.height * 0.03)

            // Doors
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x4A7A6A))
                    .frame(width: size.width * 0.1, height: size.height * 0.2)
                    .offset(
                        x: CGFloat(i - 1) * size.width * 0.22,
                        y: size.height * 0.22
                    )
            }

            // ROSEBUD MOTEL sign
            Text("ROSEBUD MOTEL")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x8A2A2A))
                .offset(y: -size.height * 0.12)

            // Parking lot
            Rectangle()
                .fill(Color(hex: 0x5A5A5A))
                .frame(height: size.height * 0.15)
                .offset(y: size.height * 0.42)
        }
    }

    // MARK: - The Office — Dunder Mifflin

    private func theOfficeScene(size: CGSize) -> some View {
        ZStack {
            // Beige office walls
            LinearGradient(
                colors: [Color(hex: 0xD8D0C0), Color(hex: 0xC8C0B0)],
                startPoint: .top, endPoint: .bottom
            )

            // Carpet
            Rectangle()
                .fill(Color(hex: 0x7A8A7A))
                .frame(height: size.height * 0.25)
                .offset(y: size.height * 0.38)

            // Window blinds (back wall)
            VStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(hex: 0xE8E0D0))
                        .frame(width: size.width * 0.35, height: 2)
                }
            }
            .offset(y: -size.height * 0.15)

            // Window frame
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(hex: 0xB0A890), lineWidth: 2)
                .frame(width: size.width * 0.38, height: size.height * 0.35)
                .offset(y: -size.height * 0.12)

            // Desk
            Rectangle()
                .fill(Color(hex: 0x8A7A60))
                .frame(width: size.width * 0.45, height: size.height * 0.05)
                .offset(x: -size.width * 0.15, y: size.height * 0.2)

            // Paper stack
            Rectangle()
                .fill(.white.opacity(0.8))
                .frame(width: size.width * 0.06, height: size.height * 0.04)
                .offset(x: -size.width * 0.25, y: size.height * 0.17)

            // Coffee mug
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(hex: 0xE8E0D0))
                .frame(width: 6, height: 8)
                .offset(x: -size.width * 0.08, y: size.height * 0.16)
        }
    }

    // MARK: - Friends — Central Perk

    private func friendsScene(size: CGSize) -> some View {
        ZStack {
            // Warm coffee shop interior
            LinearGradient(
                colors: [Color(hex: 0x6A4030), Color(hex: 0x8A5A40), Color(hex: 0x5A3828)],
                startPoint: .top, endPoint: .bottom
            )

            // Brick wall texture
            ForEach(0..<8, id: \.self) { row in
                ForEach(0..<12, id: \.self) { col in
                    let offset = row % 2 == 0 ? 0.0 : size.width * 0.04
                    Rectangle()
                        .fill(Color(hex: 0x7A4A30).opacity(Double.random(in: 0.3...0.5)))
                        .frame(width: size.width * 0.08, height: size.height * 0.05)
                        .offset(
                            x: CGFloat(col) * size.width * 0.08 - size.width * 0.44 + offset,
                            y: CGFloat(row) * size.height * 0.065 - size.height * 0.35
                        )
                }
            }

            // Orange couch
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xCC6622))
                .frame(width: size.width * 0.5, height: size.height * 0.18)
                .offset(y: size.height * 0.25)

            // Couch back
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xBB5518))
                .frame(width: size.width * 0.52, height: size.height * 0.12)
                .offset(y: size.height * 0.13)

            // Coffee table
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: 0x5A3A20))
                .frame(width: size.width * 0.3, height: size.height * 0.04)
                .offset(y: size.height * 0.35)

            // CENTRAL PERK sign
            Text("CENTRAL PERK")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: 0xE8D0A0))
                .offset(y: -size.height * 0.38)
        }
    }

    // MARK: - Rick and Morty — Garage Lab

    private func rickAndMortyScene(size: CGSize) -> some View {
        ZStack {
            // Dark lab
            LinearGradient(
                colors: [Color(hex: 0x1A2A1A), Color(hex: 0x0A1A0A)],
                startPoint: .top, endPoint: .bottom
            )

            // Portal glow (animated)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x44FF88).opacity(0.6), Color(hex: 0x22AA44).opacity(0.2), .clear],
                        center: .center, startRadius: 5, endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .offset(x: size.width * 0.25, y: -size.height * 0.1)
                .scaleEffect(1.0 + sin(Double(animTick) * 0.3) * 0.08)

            // Portal spiral
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: 0x44FF88).opacity(0.3), lineWidth: 1.5)
                    .frame(width: CGFloat(20 + i * 20), height: CGFloat(20 + i * 20))
                    .offset(x: size.width * 0.25, y: -size.height * 0.1)
                    .rotationEffect(.degrees(Double(animTick * 3 + i * 40)))
            }

            // Concrete floor
            Rectangle()
                .fill(Color(hex: 0x3A3A3A))
                .frame(height: size.height * 0.2)
                .offset(y: size.height * 0.4)

            // Workbench
            Rectangle()
                .fill(Color(hex: 0x5A4A3A))
                .frame(width: size.width * 0.4, height: size.height * 0.05)
                .offset(x: -size.width * 0.2, y: size.height * 0.22)

            // Beakers / flasks
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x88DDAA).opacity(0.5))
                    .frame(width: 5, height: CGFloat(8 + i * 3))
                    .offset(
                        x: -size.width * 0.25 + CGFloat(i) * 10,
                        y: size.height * 0.16
                    )
            }
        }
    }

    // MARK: - Sherlock — 221B Baker Street

    private func sherlockScene(size: CGSize) -> some View {
        ZStack {
            // Dark Victorian interior
            LinearGradient(
                colors: [Color(hex: 0x2A2020), Color(hex: 0x3A2A20), Color(hex: 0x1A1515)],
                startPoint: .top, endPoint: .bottom
            )

            // Wallpaper pattern
            ForEach(0..<6, id: \.self) { row in
                ForEach(0..<8, id: \.self) { col in
                    Text("◆")
                        .font(.system(size: 5))
                        .foregroundStyle(Color(hex: 0x5A4A3A).opacity(0.3))
                        .offset(
                            x: CGFloat(col) * size.width * 0.13 - size.width * 0.45,
                            y: CGFloat(row) * size.height * 0.12 - size.height * 0.35
                        )
                }
            }

            // Fireplace
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: 0x4A3A2A))
                .frame(width: size.width * 0.25, height: size.height * 0.35)
                .offset(x: size.width * 0.3, y: size.height * 0.08)

            // Fire glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFF8833).opacity(0.6), Color(hex: 0xFF4400).opacity(0.2), .clear],
                        center: .center, startRadius: 2, endRadius: 25
                    )
                )
                .frame(width: 50, height: 30)
                .offset(x: size.width * 0.3, y: size.height * 0.2)
                .scaleEffect(1.0 + sin(Double(animTick) * 0.4) * 0.1)

            // Wooden floor
            Rectangle()
                .fill(Color(hex: 0x4A3A28))
                .frame(height: size.height * 0.2)
                .offset(y: size.height * 0.4)

            // Armchair silhouette
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0x5A3A2A))
                .frame(width: size.width * 0.15, height: size.height * 0.2)
                .offset(x: -size.width * 0.3, y: size.height * 0.2)

            // 221B
            Text("221B")
                .font(.system(size: 7, weight: .bold, design: .serif))
                .foregroundStyle(Color(hex: 0xC0A878).opacity(0.5))
                .offset(y: -size.height * 0.4)
        }
    }

    // MARK: - Breaking Bad — Lab

    private func breakingBadScene(size: CGSize) -> some View {
        ZStack {
            // Yellow-amber industrial
            LinearGradient(
                colors: [Color(hex: 0x3A3020), Color(hex: 0x4A3A18), Color(hex: 0x2A2010)],
                startPoint: .top, endPoint: .bottom
            )

            // Hazard stripe on floor
            ForEach(0..<10, id: \.self) { i in
                Rectangle()
                    .fill(i % 2 == 0 ? Color(hex: 0xE8C020) : Color(hex: 0x2A2A2A))
                    .frame(width: size.width * 0.12, height: size.height * 0.04)
                    .offset(
                        x: CGFloat(i) * size.width * 0.12 - size.width * 0.5,
                        y: size.height * 0.42
                    )
            }

            // Lab equipment — big flask
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x88AACC).opacity(0.4))
                .frame(width: size.width * 0.08, height: size.height * 0.25)
                .offset(x: -size.width * 0.35, y: 0)

            // Tube connecting flasks
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color(hex: 0xAAAAAA).opacity(0.5))
                .frame(width: size.width * 0.15, height: 2)
                .offset(x: -size.width * 0.25, y: -size.height * 0.05)

            // Second flask
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x44CC88).opacity(0.5))
                .frame(width: size.width * 0.06, height: size.height * 0.18)
                .offset(x: -size.width * 0.15, y: size.height * 0.04)

            // Metal table
            Rectangle()
                .fill(Color(hex: 0x8A8A8A))
                .frame(width: size.width * 0.5, height: size.height * 0.03)
                .offset(y: size.height * 0.22)

            // Concrete floor
            Rectangle()
                .fill(Color(hex: 0x4A4A40))
                .frame(height: size.height * 0.18)
                .offset(y: size.height * 0.41)

            // Blue crystals
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x44AAEE).opacity(0.7))
                    .frame(width: 4, height: CGFloat(6 + i * 2))
                    .rotationEffect(.degrees(Double(i * 15 - 20)))
                    .offset(
                        x: size.width * 0.2 + CGFloat(i) * 7,
                        y: size.height * 0.15
                    )
            }
        }
    }

    // MARK: - Iron Man — Workshop / HUD

    private func ironManScene(size: CGSize) -> some View {
        ZStack {
            // Dark high-tech
            LinearGradient(
                colors: [Color(hex: 0x0A1020), Color(hex: 0x0A0A1A)],
                startPoint: .top, endPoint: .bottom
            )

            // HUD grid lines
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(Color(hex: 0x2244AA).opacity(0.15))
                    .frame(width: 1, height: size.height)
                    .offset(x: CGFloat(i) * size.width * 0.13 - size.width * 0.45)
            }
            ForEach(0..<6, id: \.self) { i in
                Rectangle()
                    .fill(Color(hex: 0x2244AA).opacity(0.15))
                    .frame(width: size.width, height: 1)
                    .offset(y: CGFloat(i) * size.height * 0.18 - size.height * 0.4)
            }

            // Arc reactor glow (center)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x44BBFF).opacity(0.4), Color(hex: 0x2266AA).opacity(0.1), .clear],
                        center: .center, startRadius: 5, endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(1.0 + sin(Double(animTick) * 0.25) * 0.05)

            // Holographic panels
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(hex: 0x44AAFF).opacity(0.3), lineWidth: 1)
                .frame(width: size.width * 0.2, height: size.height * 0.25)
                .offset(x: -size.width * 0.3, y: -size.height * 0.15)
                .rotationEffect(.degrees(-5))

            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(hex: 0x44AAFF).opacity(0.2), lineWidth: 1)
                .frame(width: size.width * 0.15, height: size.height * 0.2)
                .offset(x: size.width * 0.32, y: -size.height * 0.2)
                .rotationEffect(.degrees(8))

            // Floor — workshop concrete
            Rectangle()
                .fill(Color(hex: 0x2A2A30))
                .frame(height: size.height * 0.2)
                .offset(y: size.height * 0.4)

            // Floating data text
            Text("JARVIS v4.2")
                .font(.system(size: 5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: 0x44AAFF).opacity(0.4))
                .offset(x: -size.width * 0.3, y: -size.height * 0.3)
        }
    }

    // MARK: - Scene Variants (2 extra locations per theme)

    // --- Silicon Valley ---

    /// Rooftop patio at night — string lights, city skyline
    private func siliconValleyRooftopScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A0E1A), Color(hex: 0x1A1E30)], startPoint: .top, endPoint: .bottom)
            // City skyline
            ForEach(0..<8, id: \.self) { i in
                let h = CGFloat.random(in: 0.2...0.45)
                Rectangle().fill(Color(hex: 0x1A2040).opacity(0.8))
                    .frame(width: size.width * 0.08, height: size.height * h)
                    .offset(x: CGFloat(i) * size.width * 0.12 - size.width * 0.44, y: size.height * (0.5 - h / 2))
            }
            // String lights
            ForEach(0..<7, id: \.self) { i in
                Circle().fill(Color(hex: 0xFFDD66).opacity(i % 2 == animTick % 2 ? 0.8 : 0.3))
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat(i) * 22 - 66, y: -size.height * 0.3 + sin(Double(i)) * 5)
            }
            // Railing
            Rectangle().fill(Color(hex: 0x4A4A5A)).frame(width: size.width, height: 3).offset(y: size.height * 0.3)
            // Floor
            Rectangle().fill(Color(hex: 0x3A3A40)).frame(height: size.height * 0.18).offset(y: size.height * 0.41)
        }
    }

    /// Erlich's garage — dim, messy, whiteboard
    private func siliconValleyGarageScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2520), Color(hex: 0x1A1510)], startPoint: .top, endPoint: .bottom)
            // Garage door lines
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x4A4035).opacity(0.5)).frame(width: size.width * 0.9, height: 2)
                    .offset(y: -size.height * 0.3 + CGFloat(i) * 12)
            }
            // Whiteboard
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xE8E8E0))
                .frame(width: size.width * 0.25, height: size.height * 0.3)
                .offset(x: size.width * 0.28, y: -size.height * 0.1)
            // Scribbles on whiteboard
            RoundedRectangle(cornerRadius: 0.5).fill(Color(hex: 0x3344AA).opacity(0.4))
                .frame(width: size.width * 0.15, height: 1).offset(x: size.width * 0.28, y: -size.height * 0.15)
            RoundedRectangle(cornerRadius: 0.5).fill(Color(hex: 0xCC2222).opacity(0.4))
                .frame(width: size.width * 0.1, height: 1).offset(x: size.width * 0.25, y: -size.height * 0.08)
            // Concrete floor
            Rectangle().fill(Color(hex: 0x4A4A44)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
            // Single hanging bulb
            Circle().fill(Color(hex: 0xFFEE88).opacity(0.5 + sin(Double(animTick) * 0.15) * 0.2))
                .frame(width: 8, height: 8).offset(y: -size.height * 0.35)
        }
    }

    // --- Schitt's Creek ---

    /// Café Tropical — warm interior with plants
    private func schittsCreekCafeScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x5A4030), Color(hex: 0x3A2A1A)], startPoint: .top, endPoint: .bottom)
            // Counter
            Rectangle().fill(Color(hex: 0x6A5040)).frame(width: size.width * 0.8, height: size.height * 0.04).offset(y: size.height * 0.15)
            // Menu board
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2A2A20)).frame(width: size.width * 0.3, height: size.height * 0.2).offset(y: -size.height * 0.2)
            // Tropical plant (left)
            Ellipse().fill(Color(hex: 0x2A7A3A).opacity(0.7)).frame(width: 20, height: 30).offset(x: -size.width * 0.35, y: 0)
            // Warm lighting
            Circle().fill(Color(hex: 0xFFAA44).opacity(0.15)).frame(width: 120, height: 120).offset(y: -size.height * 0.2)
            // Tile floor
            Rectangle().fill(Color(hex: 0x8A7A6A)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
        }
    }

    /// Town Hall — wood paneling, podium
    private func schittsCreekTownHallScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4A3A28), Color(hex: 0x3A2A18)], startPoint: .top, endPoint: .bottom)
            // Wood paneling
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x5A4A35).opacity(0.6)).frame(width: 2, height: size.height * 0.6)
                    .offset(x: CGFloat(i) * size.width * 0.18 - size.width * 0.44, y: -size.height * 0.1)
            }
            // Podium
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x6A5A44)).frame(width: size.width * 0.15, height: size.height * 0.25).offset(y: size.height * 0.12)
            // Flag
            Rectangle().fill(Color(hex: 0xAA2233).opacity(0.5)).frame(width: 8, height: 20).offset(x: size.width * 0.3, y: -size.height * 0.15)
            // Floor
            Rectangle().fill(Color(hex: 0x7A6A5A)).frame(height: size.height * 0.18).offset(y: size.height * 0.41)
        }
    }

    // --- The Office ---

    /// Warehouse — industrial, high ceilings, boxes
    private func theOfficeWarehouseScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x2A2A2A)], startPoint: .top, endPoint: .bottom)
            // Shelving units
            ForEach(0..<3, id: \.self) { i in
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Color(hex: 0x6A5A4A)).frame(width: size.width * 0.15, height: 3)
                    }
                }
                .offset(x: CGFloat(i) * size.width * 0.3 - size.width * 0.3, y: -size.height * 0.1)
            }
            // Boxes
            Rectangle().fill(Color(hex: 0x8A7A5A)).frame(width: 18, height: 14).offset(x: -size.width * 0.2, y: size.height * 0.2)
            Rectangle().fill(Color(hex: 0x7A6A4A)).frame(width: 14, height: 12).offset(x: -size.width * 0.12, y: size.height * 0.22)
            // Concrete floor
            Rectangle().fill(Color(hex: 0x5A5A58)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
            // Hanging light
            Circle().fill(Color(hex: 0xFFEE88).opacity(0.3)).frame(width: 60, height: 60).offset(y: -size.height * 0.2)
        }
    }

    /// Break room — fridge, table, vending machine
    private func theOfficeBreakRoomScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xD8D0C0), Color(hex: 0xC8C0B0)], startPoint: .top, endPoint: .bottom)
            // Fridge
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xE8E8E8)).frame(width: size.width * 0.1, height: size.height * 0.4).offset(x: size.width * 0.35, y: 0)
            // Table
            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x8A7A6A)).frame(width: size.width * 0.3, height: size.height * 0.03).offset(y: size.height * 0.15)
            // Vending machine
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x3A3A6A)).frame(width: size.width * 0.1, height: size.height * 0.35).offset(x: -size.width * 0.35, y: size.height * 0.02)
            // Fluorescent light
            Rectangle().fill(Color(hex: 0xFFFFEE).opacity(0.6)).frame(width: size.width * 0.4, height: 3).offset(y: -size.height * 0.4)
            // Linoleum floor
            Rectangle().fill(Color(hex: 0xB8B0A0)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
        }
    }

    // --- Friends ---

    /// Central Perk at night — darker, cozy lamplight
    private func friendsCentralPerkNightScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A1810), Color(hex: 0x1A0E08)], startPoint: .top, endPoint: .bottom)
            // Couch silhouette
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x6A3A2A).opacity(0.6))
                .frame(width: size.width * 0.35, height: size.height * 0.15).offset(y: size.height * 0.2)
            // Warm lamp glow
            Circle().fill(Color(hex: 0xFFAA33).opacity(0.25 + sin(Double(animTick) * 0.1) * 0.08))
                .frame(width: 100, height: 100).offset(x: -size.width * 0.15, y: -size.height * 0.1)
            // Window with city night
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x0A1030)).frame(width: size.width * 0.2, height: size.height * 0.25).offset(x: size.width * 0.3, y: -size.height * 0.15)
            // Window glow
            RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x3A3A5A).opacity(0.5), lineWidth: 1).frame(width: size.width * 0.2, height: size.height * 0.25).offset(x: size.width * 0.3, y: -size.height * 0.15)
            // Wood floor
            Rectangle().fill(Color(hex: 0x3A2A1A)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
        }
    }

    /// NYC rooftop — skyline, water tower
    private func friendsRooftopScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A2040), Color(hex: 0x3A2848)], startPoint: .top, endPoint: .bottom)
            // Buildings
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x2A2A3A))
                    .frame(width: size.width * 0.1, height: size.height * CGFloat(0.15 + Double(i % 3) * 0.1))
                    .offset(x: CGFloat(i) * size.width * 0.15 - size.width * 0.38, y: size.height * 0.25)
            }
            // Water tower
            Ellipse().fill(Color(hex: 0x5A5A5A)).frame(width: 16, height: 10).offset(x: size.width * 0.2, y: -size.height * 0.05)
            VStack(spacing: 0) {
                Rectangle().fill(Color(hex: 0x5A5A5A)).frame(width: 2, height: 12)
                Rectangle().fill(Color(hex: 0x5A5A5A)).frame(width: 2, height: 12)
            }.offset(x: size.width * 0.2, y: size.height * 0.06)
            // Stars
            ForEach(0..<10, id: \.self) { i in
                Circle().fill(.white.opacity(0.4 + sin(Double(animTick + i * 7) * 0.2) * 0.3))
                    .frame(width: 2, height: 2)
                    .offset(x: CGFloat(i * 37 % 300) - 150, y: -size.height * 0.35 + CGFloat(i * 23 % 40))
            }
            // Floor
            Rectangle().fill(Color(hex: 0x4A4A4A)).frame(height: size.height * 0.15).offset(y: size.height * 0.42)
        }
    }

    // --- Rick and Morty ---

    /// Alien planet — strange sky, weird flora
    private func rickAndMortyAlienPlanetScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4A1A5A), Color(hex: 0x2A3A1A), Color(hex: 0x1A2A0A)], startPoint: .top, endPoint: .bottom)
            // Alien moons
            Circle().fill(Color(hex: 0xCC88DD).opacity(0.4)).frame(width: 30, height: 30).offset(x: size.width * 0.3, y: -size.height * 0.3)
            Circle().fill(Color(hex: 0x88DDAA).opacity(0.3)).frame(width: 18, height: 18).offset(x: -size.width * 0.25, y: -size.height * 0.25)
            // Strange plants
            Ellipse().fill(Color(hex: 0x44AA66).opacity(0.6)).frame(width: 25, height: 35).offset(x: -size.width * 0.3, y: size.height * 0.15)
            Ellipse().fill(Color(hex: 0xAA44CC).opacity(0.5)).frame(width: 18, height: 28).offset(x: size.width * 0.35, y: size.height * 0.18)
            // Glowing ground
            Rectangle().fill(Color(hex: 0x3A5A2A)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
            // Floating particles
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(Color(hex: 0x44FFAA).opacity(0.5))
                    .frame(width: 3, height: 3)
                    .offset(x: CGFloat(i * 50 % 250) - 125, y: sin(Double(animTick + i * 10) * 0.15) * 20)
            }
        }
    }

    /// Inside the spaceship — control panels, windshield
    private func rickAndMortySpaceshipScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A0A1A), Color(hex: 0x1A1A2A)], startPoint: .top, endPoint: .bottom)
            // Windshield — stars
            ForEach(0..<15, id: \.self) { i in
                Circle().fill(.white.opacity(0.6))
                    .frame(width: CGFloat(1 + i % 2), height: CGFloat(1 + i % 2))
                    .offset(x: CGFloat(i * 41 % 340) - 170, y: CGFloat(i * 29 % 100) - 70)
            }
            // Dashboard
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x3A3A4A))
                .frame(width: size.width * 0.9, height: size.height * 0.2).offset(y: size.height * 0.3)
            // Control lights
            ForEach(0..<5, id: \.self) { i in
                Circle().fill([Color(hex: 0xFF4444), Color(hex: 0x44FF44), Color(hex: 0x4444FF), Color(hex: 0xFFFF44), Color(hex: 0xFF44FF)][i].opacity(i == animTick % 5 ? 0.9 : 0.2))
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat(i) * 16 - 32, y: size.height * 0.25)
            }
            // Floor
            Rectangle().fill(Color(hex: 0x2A2A30)).frame(height: size.height * 0.1).offset(y: size.height * 0.45)
        }
    }

    // --- Sherlock ---

    /// Dark London alley — fog, gas lamp, cobblestones
    private func sherlockAlleyScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A1A2A), Color(hex: 0x2A2A30)], startPoint: .top, endPoint: .bottom)
            // Brick walls
            ForEach(0..<12, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x4A3A30).opacity(0.6))
                    .frame(width: size.width * 0.08, height: size.height * 0.06)
                    .offset(x: -size.width * 0.4, y: CGFloat(i) * size.height * 0.08 - size.height * 0.4)
            }
            // Gas lamp
            Circle().fill(Color(hex: 0xFFAA44).opacity(0.4 + sin(Double(animTick) * 0.2) * 0.15))
                .frame(width: 12, height: 12).offset(x: size.width * 0.25, y: -size.height * 0.25)
            // Lamp glow halo
            Circle().fill(Color(hex: 0xFFAA44).opacity(0.08))
                .frame(width: 80, height: 80).offset(x: size.width * 0.25, y: -size.height * 0.2)
            // Fog layer
            Rectangle().fill(Color(hex: 0x8A8A9A).opacity(0.08 + sin(Double(animTick) * 0.05) * 0.04))
                .frame(height: size.height * 0.3).offset(y: size.height * 0.15)
            // Cobblestone floor
            Rectangle().fill(Color(hex: 0x4A4A48)).frame(height: size.height * 0.2).offset(y: size.height * 0.4)
        }
    }

    /// Morgue — cold, clinical, blue-green light
    private func sherlockMorgueScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A2A2A), Color(hex: 0x0A1A1A)], startPoint: .top, endPoint: .bottom)
            // Metal table
            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x8A8A8A)).frame(width: size.width * 0.5, height: size.height * 0.03).offset(y: size.height * 0.15)
            // Table legs
            Rectangle().fill(Color(hex: 0x7A7A7A)).frame(width: 2, height: size.height * 0.15).offset(x: -size.width * 0.2, y: size.height * 0.25)
            Rectangle().fill(Color(hex: 0x7A7A7A)).frame(width: 2, height: size.height * 0.15).offset(x: size.width * 0.2, y: size.height * 0.25)
            // Cold light
            Rectangle().fill(Color(hex: 0x88CCCC).opacity(0.15)).frame(width: size.width * 0.3, height: 2).offset(y: -size.height * 0.38)
            // Tile floor
            Rectangle().fill(Color(hex: 0x3A4A4A)).frame(height: size.height * 0.18).offset(y: size.height * 0.41)
        }
    }

    // --- Breaking Bad ---

    /// Desert — vast, hot, RV silhouette
    private func breakingBadDesertScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x88AACC), Color(hex: 0xDDCC88), Color(hex: 0xCCAA66)], startPoint: .top, endPoint: .bottom)
            // Sun
            Circle().fill(Color(hex: 0xFFDD44).opacity(0.6)).frame(width: 25, height: 25).offset(x: size.width * 0.3, y: -size.height * 0.3)
            // RV silhouette
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xD8D0C0)).frame(width: size.width * 0.2, height: size.height * 0.15).offset(x: -size.width * 0.25, y: size.height * 0.18)
            // Distant mesas
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xAA8866).opacity(0.5)).frame(width: size.width * 0.15, height: size.height * 0.12).offset(x: size.width * 0.3, y: size.height * 0.15)
            // Sand floor
            Rectangle().fill(Color(hex: 0xCCBB88)).frame(height: size.height * 0.25).offset(y: size.height * 0.38)
        }
    }

    /// Laundry facility — industrial, blue tint
    private func breakingBadLaundryScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A3040), Color(hex: 0x1A2030)], startPoint: .top, endPoint: .bottom)
            // Washing machines
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xE8E8E0))
                    .frame(width: size.width * 0.1, height: size.height * 0.2)
                    .offset(x: CGFloat(i) * size.width * 0.14 - size.width * 0.21, y: size.height * 0.1)
                // Door circle
                Circle().stroke(Color(hex: 0x8A8A8A), lineWidth: 1)
                    .frame(width: size.width * 0.05, height: size.width * 0.05)
                    .offset(x: CGFloat(i) * size.width * 0.14 - size.width * 0.21, y: size.height * 0.1)
            }
            // Fluorescent blue light
            Rectangle().fill(Color(hex: 0x88AADD).opacity(0.12)).frame(width: size.width, height: size.height)
            // Floor
            Rectangle().fill(Color(hex: 0x3A3A40)).frame(height: size.height * 0.18).offset(y: size.height * 0.41)
        }
    }

    // --- Iron Man ---

    /// Sky — flying, clouds, HUD overlay
    private func ironManSkyScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2244AA), Color(hex: 0x4488CC), Color(hex: 0x88BBDD)], startPoint: .top, endPoint: .bottom)
            // Clouds
            ForEach(0..<4, id: \.self) { i in
                Ellipse().fill(.white.opacity(0.2))
                    .frame(width: CGFloat(40 + i * 15), height: CGFloat(12 + i * 4))
                    .offset(
                        x: CGFloat(i * 80 % 300) - 150 + sin(Double(animTick + i * 20) * 0.03) * 10,
                        y: CGFloat(i * 50 % 120) - 60
                    )
            }
            // HUD elements
            Circle().stroke(Color(hex: 0xFF4444).opacity(0.4), lineWidth: 1).frame(width: 30, height: 30).offset(x: size.width * 0.3, y: -size.height * 0.2)
            Text("ALT 12,400")
                .font(.system(size: 5, design: .monospaced))
                .foregroundStyle(Color(hex: 0x44FFAA).opacity(0.5))
                .offset(x: -size.width * 0.3, y: -size.height * 0.35)
            Text("SPD 890")
                .font(.system(size: 5, design: .monospaced))
                .foregroundStyle(Color(hex: 0x44FFAA).opacity(0.5))
                .offset(x: -size.width * 0.3, y: -size.height * 0.28)
        }
    }

    /// Avengers HQ — modern, circular table, holograms
    private func ironManAvengersHQScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A1A2A), Color(hex: 0x0A0A15)], startPoint: .top, endPoint: .bottom)
            // Circular table
            Ellipse().fill(Color(hex: 0x3A3A4A)).frame(width: size.width * 0.5, height: size.height * 0.08).offset(y: size.height * 0.2)
            // Holographic A logo
            Text("A").font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x4488FF).opacity(0.2 + sin(Double(animTick) * 0.15) * 0.1))
                .offset(y: -size.height * 0.05)
            // Ambient ceiling lights
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x4488FF).opacity(0.1)).frame(width: size.width * 0.25, height: 1)
                    .offset(y: -size.height * 0.38 + CGFloat(i) * 4)
            }
            // Floor
            Rectangle().fill(Color(hex: 0x2A2A30)).frame(height: size.height * 0.18).offset(y: size.height * 0.41)
        }
    }
}
