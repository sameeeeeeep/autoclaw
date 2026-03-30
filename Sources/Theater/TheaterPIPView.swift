import SwiftUI

/// Picture-in-Picture floating widget for SiliconValley Theater.
/// Full animated stage: themed background, two character sprites with idle/talking/gesturing
/// animations, dialogue bubbles, and a scrolling transcript.
public struct TheaterPIPView<Source: TheaterDataSource>: View {
    @ObservedObject var dataSource: Source
    let dialogThemeId: String
    let onDismiss: () -> Void

    public init(dataSource: Source, dialogThemeId: String, onDismiss: @escaping () -> Void) {
        self.dataSource = dataSource
        self.dialogThemeId = dialogThemeId
        self.onDismiss = onDismiss
    }

    @Environment(\.colorScheme) private var colorScheme
    private var theme: TheaterColors { TheaterColors(colorScheme: colorScheme) }

    private var dialogTheme: DialogTheme {
        DialogTheme.find(dialogThemeId)
    }

    // Animation timer — drives sprite state at ~7fps
    @State private var animTick: Int = 0
    @State private var char1Anim = SpriteAnimContext()
    @State private var char2Anim = SpriteAnimContext()
    @State private var timer: Timer?

    // displayedLineIndex drives bubble + transcript highlight, synced from TTS currentLineIndex
    @State private var displayedLineIndex: Int = -1

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Stage — animated scene with characters + dialog bubble
            stageView
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)

            // Transcript — scrolling dialog history
            if !dataSource.sessionDialog.isEmpty {
                Divider()
                    .background(theme.border)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                transcriptView
                    .frame(maxHeight: 100)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            } else {
                emptyHint
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 380)
        .modifier(TheaterLiquidGlass(fallbackColor: theme.card))
        .theaterGlow(
            color: TheaterColors.teal,
            cornerRadius: 16,
            state: dataSource.dialogVoice.isSpeaking ? .thinking : .off
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 20, y: 6)
        .onAppear { startAnimationLoop() }
        .onDisappear { stopAnimationLoop() }
        .onChange(of: dataSource.dialogVoice.currentLineIndex) {
            let idx = dataSource.dialogVoice.currentLineIndex
            if idx >= 0 && idx < dataSource.sessionDialog.count {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayedLineIndex = idx
                }
            } else if idx < 0 {
                // TTS finished — keep last bubble visible briefly, then clear
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard dataSource.dialogVoice.currentLineIndex < 0 else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        displayedLineIndex = -1
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            // Theater badge
            HStack(spacing: 4) {
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(TheaterColors.teal)
                Text(dialogTheme.show)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TheaterColors.teal)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(TheaterColors.teal.opacity(0.12))
            .clipShape(Capsule())

            Spacer()

            // Speaking indicator
            if dataSource.dialogVoice.isSpeaking {
                HStack(spacing: 3) {
                    speakingDots
                    Text(dataSource.dialogVoice.isPlayingFiller ? "Filler" : "Speaking")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(dataSource.dialogVoice.isPlayingFiller ? TheaterColors.purple.opacity(0.6) : TheaterColors.teal.opacity(0.6))
                }
            }

            // Close
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 16, height: 16)
                    .background(theme.textMuted.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stage

    private var stageView: some View {
        let chars = SpriteLibrary.characters(for: dialogTheme.id)
        let speakingChar = currentSpeakingCharacter

        return ZStack {
            // Background scene
            TheaterSceneBackground(themeId: dialogTheme.id, animTick: animTick)

            // Stage floor gradient (subtle, grounds the characters)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.3)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 40)
            }

            // Character 1 (left)
            SpriteView(
                appearance: chars.0,
                animState: spriteState(for: dialogTheme.char1, speaking: speakingChar),
                animContext: char1Anim,
                facingRight: true
            )
            .opacity(chars.0.accessory == .holographic ? 0.7 + sin(Double(animTick) * 0.3) * 0.15 : 1.0)
            .offset(x: -70, y: 35)
            // Subtle shadow under character
            .background(
                Ellipse()
                    .fill(.black.opacity(0.2))
                    .frame(width: 40, height: 8)
                    .offset(x: -70, y: 90)
                    .blur(radius: 2)
            )

            // Character 2 (right)
            SpriteView(
                appearance: chars.1,
                animState: spriteState(for: dialogTheme.char2, speaking: speakingChar),
                animContext: char2Anim,
                facingRight: false
            )
            .opacity(chars.1.accessory == .holographic ? 0.7 + sin(Double(animTick) * 0.3) * 0.15 : 1.0)
            .offset(x: 70, y: 35)
            .background(
                Ellipse()
                    .fill(.black.opacity(0.2))
                    .frame(width: 40, height: 8)
                    .offset(x: 70, y: 90)
                    .blur(radius: 2)
            )

            // Dialog bubble (above the speaking character)
            if displayedLineIndex >= 0 && displayedLineIndex < dataSource.sessionDialog.count {
                let line = dataSource.sessionDialog[displayedLineIndex]
                let isChar1 = line.character == dialogTheme.char1

                dialogBubble(text: line.line, pointsLeft: isChar1)
                    .offset(x: isChar1 ? -20 : 20, y: -60)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: isChar1 ? .bottomLeading : .bottomTrailing)
                            .combined(with: .opacity),
                        removal: .opacity
                    ))
                    .id("bubble-\(displayedLineIndex)")
            }
        }
    }

    // MARK: - Dialog Bubble

    private func dialogBubble(text: String, pointsLeft: Bool) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.75))
                )
                .frame(maxWidth: 220)

            // Bubble tail
            Triangle()
                .fill(.black.opacity(0.75))
                .frame(width: 10, height: 6)
                .offset(x: pointsLeft ? -30 : 30)
        }
    }

    // MARK: - Transcript

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(dataSource.sessionDialog.enumerated()), id: \.element.id) { idx, line in
                        let isChar1 = line.character == dialogTheme.char1
                        let charColor: Color = isChar1 ? TheaterColors.teal : TheaterColors.purple
                        let isActive = idx == displayedLineIndex

                        HStack(alignment: .top, spacing: 6) {
                            Text(line.character)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(charColor.opacity(isActive ? 1 : 0.6))
                                .frame(width: 50, alignment: .trailing)

                            Text(line.line)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textPrimary.opacity(isActive ? 1 : 0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
                        .id(line.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: dataSource.sessionDialog.count) {
                if let last = dataSource.sessionDialog.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty Hint

    private var emptyHint: some View {
        VStack(spacing: 6) {
            if dataSource.isGeneratingPrompt {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(TheaterColors.teal)
                    Text("Writing the script\u{2026}")
                        .font(.system(size: 10))
                        .foregroundStyle(TheaterColors.teal.opacity(0.7))
                }
            } else {
                Text("\(dialogTheme.char1) & \(dialogTheme.char2) are waiting for the scene\u{2026}")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Animation Loop

    private func startAnimationLoop() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 7.0, repeats: true) { _ in
            Task { @MainActor in
                animTick += 1
                char1Anim.advance()
                char2Anim.advance()
            }
        }
    }

    private func stopAnimationLoop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Speaking Logic

    private var currentSpeakingCharacter: String? {
        let idx = dataSource.dialogVoice.currentLineIndex
        guard dataSource.dialogVoice.isSpeaking,
              idx >= 0,
              idx < dataSource.sessionDialog.count
        else { return nil }
        return dataSource.sessionDialog[idx].character
    }

    private func spriteState(for charName: String, speaking: String?) -> SpriteAnimState {
        guard let speaking else { return .idle }
        if speaking == charName { return .talking }
        // The other character gestures/reacts while listening
        return .gesturing
    }

    // Bubble timing is now driven by DialogVoiceService.currentLineIndex
    // — no local scheduling needed. See onChange(of: currentLineIndex) above.

    // MARK: - Speaking Dots

    @State private var dotPhase = false

    private var speakingDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(TheaterColors.teal)
                    .frame(width: 3, height: 3)
                    .offset(y: dotPhase ? -2 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: dotPhase
                    )
            }
        }
        .onAppear { dotPhase = true }
    }
}

// MARK: - Triangle Shape (bubble tail)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Liquid Glass

private struct TheaterLiquidGlass: ViewModifier {
    let fallbackColor: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        } else {
            content
                .background(fallbackColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
