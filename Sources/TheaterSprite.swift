import SwiftUI

// MARK: - Character Appearance

/// Visual definition for a single character — drives the sprite renderer.
struct CharacterAppearance {
    let name: String
    let skinColor: Color
    let hairColor: Color
    let hairStyle: HairStyle
    let shirtColor: Color
    let pantsColor: Color
    let bodyBuild: BodyBuild
    let hasGlasses: Bool
    let hasBeard: Bool
    let hasGoatee: Bool
    let accessory: SpriteAccessory

    enum HairStyle {
        case short, floppy, spiky, swept, curly, bald, beanie, wig, buzz
    }
    enum BodyBuild {
        case slim, medium, stocky, tall
    }
    enum SpriteAccessory {
        case none, labCoat, tie, scarf, coat, hoodie, armor, holographic
    }
}

// MARK: - Animation State

enum SpriteAnimState {
    case idle, talking, gesturing
}

/// Tracks per-character animation timing
struct SpriteAnimContext {
    var tick: Int = 0
    var blinkTimer: Int = 0
    var isBlinking: Bool = false

    mutating func advance() {
        tick += 1
        blinkTimer += 1
        if blinkTimer > 25 { // blink every ~3.5s at 7fps
            isBlinking = true
            blinkTimer = 0
        } else if blinkTimer > 2 && isBlinking {
            isBlinking = false
        }
    }
}

// MARK: - Character Library

/// All 16 characters across 8 theme pairs
enum SpriteLibrary {
    static func characters(for themeId: String) -> (CharacterAppearance, CharacterAppearance) {
        switch themeId {
        case "gilfoyle-dinesh":
            return (gilfoyle, dinesh)
        case "david-moira":
            return (david, moira)
        case "dwight-jim":
            return (dwight, jim)
        case "chandler-joey":
            return (chandler, joey)
        case "rick-morty":
            return (rick, morty)
        case "sherlock-watson":
            return (sherlock, watson)
        case "jesse-walter":
            return (jesse, walter)
        case "tony-jarvis":
            return (tony, jarvis)
        default:
            return (gilfoyle, dinesh)
        }
    }

    // Silicon Valley
    static let gilfoyle = CharacterAppearance(
        name: "Gilfoyle", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x1A1A1A),
        hairStyle: .floppy, shirtColor: Color(hex: 0x111111), pantsColor: Color(hex: 0x222222),
        bodyBuild: .tall, hasGlasses: false, hasBeard: true, hasGoatee: false, accessory: .none
    )
    static let dinesh = CharacterAppearance(
        name: "Dinesh", skinColor: Color(hex: 0xC08050), hairColor: Color(hex: 0x0A0A0A),
        hairStyle: .short, shirtColor: Color(hex: 0x2A7A9A), pantsColor: Color(hex: 0x3A3A4A),
        bodyBuild: .medium, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )

    // Schitt's Creek
    static let david = CharacterAppearance(
        name: "David", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x0A0A0A),
        hairStyle: .swept, shirtColor: Color(hex: 0x111111), pantsColor: Color(hex: 0x0A0A0A),
        bodyBuild: .medium, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .scarf
    )
    static let moira = CharacterAppearance(
        name: "Moira", skinColor: Color(hex: 0xF5E0D0), hairColor: Color(hex: 0xE8E0D0),
        hairStyle: .wig, shirtColor: Color(hex: 0x6A2A8A), pantsColor: Color(hex: 0x3A1A5A),
        bodyBuild: .slim, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )

    // The Office
    static let dwight = CharacterAppearance(
        name: "Dwight", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x8A6A30),
        hairStyle: .buzz, shirtColor: Color(hex: 0xD4C444), pantsColor: Color(hex: 0x5A4A2A),
        bodyBuild: .stocky, hasGlasses: true, hasBeard: false, hasGoatee: false, accessory: .tie
    )
    static let jim = CharacterAppearance(
        name: "Jim", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x6A4A2A),
        hairStyle: .floppy, shirtColor: Color(hex: 0x5A8ABB), pantsColor: Color(hex: 0x4A4A5A),
        bodyBuild: .tall, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .tie
    )

    // Friends
    static let chandler = CharacterAppearance(
        name: "Chandler", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x6A4A2A),
        hairStyle: .short, shirtColor: Color(hex: 0x5A7A9A), pantsColor: Color(hex: 0x4A4A5A),
        bodyBuild: .medium, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )
    static let joey = CharacterAppearance(
        name: "Joey", skinColor: Color(hex: 0xD8B888), hairColor: Color(hex: 0x1A1A1A),
        hairStyle: .short, shirtColor: Color(hex: 0xAA3333), pantsColor: Color(hex: 0x3A3A4A),
        bodyBuild: .stocky, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )

    // Rick and Morty
    static let rick = CharacterAppearance(
        name: "Rick", skinColor: Color(hex: 0xD0D8D8), hairColor: Color(hex: 0x7AC0E0),
        hairStyle: .spiky, shirtColor: Color(hex: 0xE8E8E8), pantsColor: Color(hex: 0x6A5A3A),
        bodyBuild: .tall, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .labCoat
    )
    static let morty = CharacterAppearance(
        name: "Morty", skinColor: Color(hex: 0xF0D0A0), hairColor: Color(hex: 0x8A6A2A),
        hairStyle: .short, shirtColor: Color(hex: 0xE8D030), pantsColor: Color(hex: 0x4A6AAA),
        bodyBuild: .slim, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )

    // Sherlock
    static let sherlock = CharacterAppearance(
        name: "Sherlock", skinColor: Color(hex: 0xF0D8C0), hairColor: Color(hex: 0x1A1A2A),
        hairStyle: .curly, shirtColor: Color(hex: 0x2A2A3A), pantsColor: Color(hex: 0x1A1A2A),
        bodyBuild: .tall, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .coat
    )
    static let watson = CharacterAppearance(
        name: "Watson", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0xB09060),
        hairStyle: .short, shirtColor: Color(hex: 0xC0A878), pantsColor: Color(hex: 0x5A5A5A),
        bodyBuild: .medium, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .none
    )

    // Breaking Bad
    static let jesse = CharacterAppearance(
        name: "Jesse", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0x6A4A2A),
        hairStyle: .beanie, shirtColor: Color(hex: 0xCC3333), pantsColor: Color(hex: 0x4A4A5A),
        bodyBuild: .slim, hasGlasses: false, hasBeard: false, hasGoatee: true, accessory: .hoodie
    )
    static let walter = CharacterAppearance(
        name: "Walter", skinColor: Color(hex: 0xF0D0B0), hairColor: Color(hex: 0xA0A0A0),
        hairStyle: .bald, shirtColor: Color(hex: 0x4A8A4A), pantsColor: Color(hex: 0x5A5A4A),
        bodyBuild: .medium, hasGlasses: true, hasBeard: false, hasGoatee: true, accessory: .none
    )

    // Iron Man
    static let tony = CharacterAppearance(
        name: "Tony", skinColor: Color(hex: 0xD8B888), hairColor: Color(hex: 0x1A1A1A),
        hairStyle: .short, shirtColor: Color(hex: 0xAA2222), pantsColor: Color(hex: 0x3A3A4A),
        bodyBuild: .medium, hasGlasses: false, hasBeard: false, hasGoatee: true, accessory: .armor
    )
    static let jarvis = CharacterAppearance(
        name: "JARVIS", skinColor: Color(hex: 0x88BBEE), hairColor: Color(hex: 0x6699CC),
        hairStyle: .short, shirtColor: Color(hex: 0x4477AA), pantsColor: Color(hex: 0x335588),
        bodyBuild: .tall, hasGlasses: false, hasBeard: false, hasGoatee: false, accessory: .holographic
    )
}

// MARK: - Sprite Renderer

/// Renders an animated character sprite using SwiftUI shapes.
/// Chibi-style proportions: big head, small body, stubby limbs.
struct SpriteView: View {
    let appearance: CharacterAppearance
    let animState: SpriteAnimState
    let animContext: SpriteAnimContext
    let facingRight: Bool

    /// Scale factor for the whole sprite
    private let scale: CGFloat = 1.0
    /// Base pixel unit
    private let px: CGFloat = 3.0

    private var headSize: CGFloat {
        switch appearance.bodyBuild {
        case .slim: return 22 * px
        case .medium: return 24 * px
        case .stocky: return 26 * px
        case .tall: return 22 * px
        }
    }

    private var bodyWidth: CGFloat {
        switch appearance.bodyBuild {
        case .slim: return 16 * px
        case .medium: return 20 * px
        case .stocky: return 24 * px
        case .tall: return 18 * px
        }
    }

    private var bodyHeight: CGFloat {
        switch appearance.bodyBuild {
        case .slim: return 14 * px
        case .medium: return 16 * px
        case .stocky: return 14 * px
        case .tall: return 18 * px
        }
    }

    private var totalHeight: CGFloat { headSize + bodyHeight + 10 * px }

    // Animation offsets
    private var headBob: CGFloat {
        switch animState {
        case .talking: return sin(Double(animContext.tick) * 0.6) * 2
        case .gesturing: return -2
        case .idle: return sin(Double(animContext.tick) * 0.15) * 0.5
        }
    }

    private var bodyBounce: CGFloat {
        switch animState {
        case .talking: return sin(Double(animContext.tick) * 0.4) * 1
        case .idle: return sin(Double(animContext.tick) * 0.15) * 0.5
        case .gesturing: return 0
        }
    }

    private var armAngle: Double {
        switch animState {
        case .idle: return 0
        case .talking: return sin(Double(animContext.tick) * 0.5) * 15
        case .gesturing: return -45
        }
    }

    private var mouthOpen: Bool {
        animState == .talking && animContext.tick % 4 < 2
    }

    var body: some View {
        ZStack {
            // Legs
            legsView
                .offset(y: bodyHeight / 2 + headSize / 2 - 2)

            // Body
            bodyView
                .offset(y: headSize / 2 - 4 + bodyBounce)

            // Arms
            armsView
                .offset(y: headSize / 2 - 2 + bodyBounce)

            // Head
            headView
                .offset(y: -(bodyHeight / 2) + headBob)
        }
        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
        .frame(width: max(bodyWidth, headSize) + 20 * px, height: totalHeight + 4 * px)
        .animation(.easeInOut(duration: 0.15), value: animContext.tick)
    }

    // MARK: - Head

    private var headView: some View {
        ZStack {
            // Head shape
            Circle()
                .fill(appearance.skinColor)
                .frame(width: headSize, height: headSize)

            // Hair
            hairView

            // Face
            faceView

            // Glasses
            if appearance.hasGlasses {
                glassesView
            }

            // Facial hair
            if appearance.hasBeard {
                beardView
            }
            if appearance.hasGoatee {
                goateeView
            }
        }
    }

    private var hairView: some View {
        Group {
            switch appearance.hairStyle {
            case .short:
                Capsule()
                    .fill(appearance.hairColor)
                    .frame(width: headSize * 0.85, height: headSize * 0.5)
                    .offset(y: -headSize * 0.22)

            case .floppy:
                ZStack {
                    Capsule()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.9, height: headSize * 0.55)
                        .offset(y: -headSize * 0.2)
                    // Floppy side
                    Ellipse()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.35, height: headSize * 0.4)
                        .offset(x: headSize * 0.3, y: -headSize * 0.1)
                }

            case .spiky:
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        let angle = Double(i - 2) * 20
                        RoundedRectangle(cornerRadius: 1)
                            .fill(appearance.hairColor)
                            .frame(width: 4 * px, height: headSize * 0.35)
                            .rotationEffect(.degrees(angle))
                            .offset(x: CGFloat(i - 2) * 3 * px, y: -headSize * 0.38)
                    }
                    Capsule()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.85, height: headSize * 0.35)
                        .offset(y: -headSize * 0.25)
                }

            case .swept:
                ZStack {
                    Capsule()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.95, height: headSize * 0.55)
                        .offset(y: -headSize * 0.2)
                    Ellipse()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.5, height: headSize * 0.6)
                        .offset(x: -headSize * 0.2, y: -headSize * 0.25)
                        .rotationEffect(.degrees(-15))
                }

            case .curly:
                ZStack {
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(appearance.hairColor)
                            .frame(width: headSize * 0.25)
                            .offset(
                                x: cos(Double(i) * .pi / 3) * headSize * 0.32,
                                y: sin(Double(i) * .pi / 3) * headSize * 0.1 - headSize * 0.3
                            )
                    }
                    Capsule()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.85, height: headSize * 0.45)
                        .offset(y: -headSize * 0.22)
                }

            case .bald:
                // Just a slight hairline shadow
                Capsule()
                    .fill(appearance.hairColor.opacity(0.15))
                    .frame(width: headSize * 0.7, height: headSize * 0.2)
                    .offset(y: -headSize * 0.35)

            case .beanie:
                ZStack {
                    // Beanie body
                    Capsule()
                        .fill(Color(hex: 0x555555))
                        .frame(width: headSize * 0.95, height: headSize * 0.55)
                        .offset(y: -headSize * 0.25)
                    // Beanie rim
                    Capsule()
                        .fill(Color(hex: 0x444444))
                        .frame(width: headSize * 0.9, height: headSize * 0.15)
                        .offset(y: -headSize * 0.1)
                    // Pom
                    Circle()
                        .fill(Color(hex: 0x555555))
                        .frame(width: 4 * px)
                        .offset(y: -headSize * 0.48)
                }

            case .wig:
                ZStack {
                    // Big dramatic wig
                    Ellipse()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 1.3, height: headSize * 0.8)
                        .offset(y: -headSize * 0.15)
                    // Volume on sides
                    Ellipse()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.4, height: headSize * 0.5)
                        .offset(x: -headSize * 0.5, y: 0)
                    Ellipse()
                        .fill(appearance.hairColor)
                        .frame(width: headSize * 0.4, height: headSize * 0.5)
                        .offset(x: headSize * 0.5, y: 0)
                }

            case .buzz:
                Capsule()
                    .fill(appearance.hairColor)
                    .frame(width: headSize * 0.8, height: headSize * 0.35)
                    .offset(y: -headSize * 0.28)
            }
        }
    }

    private var faceView: some View {
        ZStack {
            // Eyes
            let eyeSpacing = headSize * 0.18
            let eyeY = -headSize * 0.02

            if animContext.isBlinking {
                // Blink — horizontal lines
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 3 * px, height: 1 * px)
                    .offset(x: -eyeSpacing, y: eyeY)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 3 * px, height: 1 * px)
                    .offset(x: eyeSpacing, y: eyeY)
            } else {
                // Open eyes
                Circle()
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 3 * px, height: 3 * px)
                    .offset(x: -eyeSpacing, y: eyeY)
                Circle()
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 3 * px, height: 3 * px)
                    .offset(x: eyeSpacing, y: eyeY)
                // Eye shine
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 1 * px, height: 1 * px)
                    .offset(x: -eyeSpacing + 1, y: eyeY - 1)
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 1 * px, height: 1 * px)
                    .offset(x: eyeSpacing + 1, y: eyeY - 1)
            }

            // Mouth
            let mouthY = headSize * 0.15
            if mouthOpen {
                Ellipse()
                    .fill(Color(hex: 0x4A2020))
                    .frame(width: 4 * px, height: 3 * px)
                    .offset(y: mouthY)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0x4A2020))
                    .frame(width: 4 * px, height: 1 * px)
                    .offset(y: mouthY)
            }
        }
    }

    private var glassesView: some View {
        let eyeSpacing = headSize * 0.18
        let eyeY = -headSize * 0.02
        return ZStack {
            // Left lens
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(hex: 0x3A3A3A), lineWidth: 1.5)
                .frame(width: 5 * px, height: 4 * px)
                .offset(x: -eyeSpacing, y: eyeY)
            // Right lens
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(hex: 0x3A3A3A), lineWidth: 1.5)
                .frame(width: 5 * px, height: 4 * px)
                .offset(x: eyeSpacing, y: eyeY)
            // Bridge
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color(hex: 0x3A3A3A))
                .frame(width: eyeSpacing * 0.8, height: 1.5)
                .offset(y: eyeY)
        }
    }

    private var beardView: some View {
        Ellipse()
            .fill(appearance.hairColor.opacity(0.6))
            .frame(width: headSize * 0.55, height: headSize * 0.35)
            .offset(y: headSize * 0.18)
    }

    private var goateeView: some View {
        Ellipse()
            .fill(appearance.hairColor.opacity(0.6))
            .frame(width: headSize * 0.2, height: headSize * 0.18)
            .offset(y: headSize * 0.22)
    }

    // MARK: - Body

    private var bodyView: some View {
        ZStack {
            // Main body/shirt
            RoundedRectangle(cornerRadius: 4 * px)
                .fill(appearance.shirtColor)
                .frame(width: bodyWidth, height: bodyHeight)

            // Accessory overlays
            switch appearance.accessory {
            case .labCoat:
                RoundedRectangle(cornerRadius: 4 * px)
                    .fill(.white.opacity(0.85))
                    .frame(width: bodyWidth + 4 * px, height: bodyHeight + 2 * px)
                // Lapels
                RoundedRectangle(cornerRadius: 1)
                    .fill(appearance.shirtColor)
                    .frame(width: bodyWidth * 0.3, height: bodyHeight * 0.5)
                    .offset(y: -bodyHeight * 0.1)

            case .tie:
                // Tie
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0xAA2222))
                    .frame(width: 3 * px, height: bodyHeight * 0.7)
                    .offset(y: bodyHeight * 0.05)

            case .scarf:
                Capsule()
                    .fill(Color(hex: 0xE8E8E8))
                    .frame(width: bodyWidth * 0.6, height: 4 * px)
                    .offset(y: -bodyHeight * 0.35)

            case .coat:
                // Long coat overlay
                RoundedRectangle(cornerRadius: 4 * px)
                    .fill(appearance.shirtColor.opacity(0.9))
                    .frame(width: bodyWidth + 6 * px, height: bodyHeight + 8 * px)
                // Collar up
                ForEach([-1, 1], id: \.self) { side in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(appearance.shirtColor)
                        .frame(width: 4 * px, height: 6 * px)
                        .offset(x: CGFloat(side) * bodyWidth * 0.25, y: -bodyHeight * 0.4)
                        .rotationEffect(.degrees(Double(-side) * 15))
                }

            case .hoodie:
                // Hood behind head area
                Capsule()
                    .fill(appearance.shirtColor.opacity(0.7))
                    .frame(width: bodyWidth * 0.7, height: 5 * px)
                    .offset(y: -bodyHeight * 0.4)
                // Pocket
                RoundedRectangle(cornerRadius: 2)
                    .fill(appearance.shirtColor.opacity(0.6))
                    .frame(width: bodyWidth * 0.6, height: bodyHeight * 0.25)
                    .offset(y: bodyHeight * 0.15)

            case .armor:
                // Arc reactor glow
                Circle()
                    .fill(Color(hex: 0x44BBFF).opacity(0.8))
                    .frame(width: 5 * px, height: 5 * px)
                    .offset(y: -bodyHeight * 0.15)
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 3 * px, height: 3 * px)
                    .offset(y: -bodyHeight * 0.15)

            case .holographic:
                // Scan lines
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.white.opacity(0.15))
                        .frame(width: bodyWidth, height: 1)
                        .offset(y: CGFloat(i) * bodyHeight * 0.25 - bodyHeight * 0.35)
                }

            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Arms

    private var armsView: some View {
        let armWidth = 4 * px
        let armLength = bodyHeight * 0.65

        return ZStack {
            // Left arm (gesturing arm)
            RoundedRectangle(cornerRadius: armWidth / 2)
                .fill(appearance.shirtColor)
                .frame(width: armWidth, height: armLength)
                .offset(y: armLength / 2 - 2)
                .rotationEffect(.degrees(armAngle), anchor: .top)
                .offset(x: -(bodyWidth / 2 + armWidth / 2 + 1))

            // Right arm (follows slightly)
            RoundedRectangle(cornerRadius: armWidth / 2)
                .fill(appearance.shirtColor)
                .frame(width: armWidth, height: armLength)
                .offset(y: armLength / 2 - 2)
                .rotationEffect(.degrees(-armAngle * 0.3), anchor: .top)
                .offset(x: bodyWidth / 2 + armWidth / 2 + 1)

            // Hands
            Circle()
                .fill(appearance.skinColor)
                .frame(width: armWidth, height: armWidth)
                .offset(y: armLength - 2)
                .rotationEffect(.degrees(armAngle), anchor: UnitPoint(x: 0.5, y: -0.3))
                .offset(x: -(bodyWidth / 2 + armWidth / 2 + 1))

            Circle()
                .fill(appearance.skinColor)
                .frame(width: armWidth, height: armWidth)
                .offset(y: armLength - 2)
                .rotationEffect(.degrees(-armAngle * 0.3), anchor: UnitPoint(x: 0.5, y: -0.3))
                .offset(x: bodyWidth / 2 + armWidth / 2 + 1)
        }
    }

    // MARK: - Legs

    private var legsView: some View {
        let legWidth = 5 * px
        let legHeight = 8 * px
        let spacing = bodyWidth * 0.2

        return HStack(spacing: spacing) {
            RoundedRectangle(cornerRadius: legWidth / 2)
                .fill(appearance.pantsColor)
                .frame(width: legWidth, height: legHeight)
            RoundedRectangle(cornerRadius: legWidth / 2)
                .fill(appearance.pantsColor)
                .frame(width: legWidth, height: legHeight)
        }
    }
}

