import SwiftUI

// MARK: - Theater Scene Backgrounds

/// Renders a themed background scene for each of the 8 dialog themes.
/// Pixel-art-inspired style with gradients and geometric shapes.
struct TheaterSceneBackground: View {
    let themeId: String
    let animTick: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                scene(for: themeId, size: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func scene(for id: String, size: CGSize) -> some View {
        switch id {
        case "gilfoyle-dinesh":       siliconValleyScene(size: size)
        case "david-moira":           schittsCreekScene(size: size)
        case "dwight-jim":            theOfficeScene(size: size)
        case "chandler-joey":         friendsScene(size: size)
        case "rick-morty":            rickAndMortyScene(size: size)
        case "sherlock-watson":       sherlockScene(size: size)
        case "jesse-walter":          breakingBadScene(size: size)
        case "tony-jarvis":           ironManScene(size: size)
        default:                      siliconValleyScene(size: size)
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
}
