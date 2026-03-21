import SwiftUI
import AppKit

// MARK: - Pill Mode

enum PillMode: String, CaseIterable {
    case ambient  = "ambient"
    case aiSearch = "aiSearch"
    case learn    = "learn"

    var icon: String {
        switch self {
        case .ambient:  return "checklist"
        case .aiSearch: return "magnifyingglass"
        case .learn:    return "brain.head.profile"
        }
    }

    var color: Color {
        switch self {
        case .ambient:  return .green
        case .aiSearch: return .accentColor
        case .learn:    return .cyan
        }
    }
}

// MARK: - Collapse Level

enum CollapseLevel: Int, CaseIterable {
    case expanded   = 0  // triple row + full status rows + mode bar + canvas + logs + dock
    case full       = 1  // triple row + mode bar + canvas + dock
    case compact    = 2  // triple row + canvas (taller) + dock
    case headerOnly = 3  // header only
    case icon       = 4  // tiny icon dot

    var height: CGFloat {
        switch self {
        case .expanded:   return 420
        case .full:       return 280
        case .compact:    return 250
        case .headerOnly: return 40
        case .icon:       return 44
        }
    }

    var width: CGFloat { self == .icon ? 44 : 220 }

    func next() -> CollapseLevel {
        CollapseLevel(rawValue: min(rawValue + 1, 4)) ?? .icon
    }
    func prev() -> CollapseLevel {
        CollapseLevel(rawValue: max(rawValue - 1, 0)) ?? .expanded
    }
}

// MARK: - Glow State

enum GlowState: Equatable { case off, enabled, thinking }

// MARK: - Color hex

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0; Scanner(string: h).scanHexInt64(&n)
        self.init(red: Double((n >> 16) & 0xFF) / 255,
                  green: Double((n >> 8) & 0xFF) / 255,
                  blue: Double(n & 0xFF) / 255)
    }
}

// MARK: - Appearance tokens (dark)

private enum Ap {
    static let textPrimary:   Color = .white
    static let textSecondary: Color = .white.opacity(0.55)
    static let textTertiary:  Color = .white.opacity(0.35)
    static let textDim:       Color = .white.opacity(0.18)
    static let textOff:       Color = .white.opacity(0.12)

    static let rowTile: Color = .white
    static let rowOff:  Double = 0.03
    static let rowOn:   Double = 0.06
    static let rowAct:  Double = 0.09

    static let borderHigh: Color = .white.opacity(0.20)
    static let borderLow:  Color = .white.opacity(0.05)
    static let borderOff:  Color = .white.opacity(0.13)
    static let sep:        Color = .white.opacity(0.07)

    static let spec:   Color = .white
    static let specOp: Double = 0.13

    static let iconBg:    Color = .white.opacity(0.08)
    static let iconOff:   Color = .white.opacity(0.15)
    static let iconFaint: Color = .white.opacity(0.06)
    static let dotOff:    Color = .white.opacity(0.10)

    static let canvasBg: Color = .black.opacity(0.58)
    static let logBg:    Color = .black.opacity(0.45)
    static let dockSep:  Color = .white.opacity(0.14)

    static let modeBgAct:     Color = .white.opacity(0.13)
    static let modeBorderAct: Color = .white.opacity(0.18)
    static let modeOff:       Color = .white.opacity(0.28)
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @Binding var collapseLevel: CollapseLevel
    @State private var pillMode: PillMode = .ambient
    @State private var micOn = false
    @State private var analysisOn = false
    @State private var codeOn = false
    @State private var screenShareOn = false

    var body: some View {
        Group {
            switch collapseLevel {
            case .icon:       iconView
            case .headerOnly: headerOnlyView
            default:          fullView
            }
        }
        .frame(width: collapseLevel.width, height: collapseLevel.height)
        .background { shell }
        .clipShape(RoundedRectangle(cornerRadius: collapseLevel == .icon ? 16 : 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: collapseLevel == .icon ? 16 : 26, style: .continuous)
            .stroke(LinearGradient(colors: [Ap.borderHigh, Ap.borderLow], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.50), radius: 36, y: 18)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: collapseLevel)
    }

    // MARK: - Icon (most collapsed)

    private var iconView: some View {
        ZStack {
            LogoImage(size: 22)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { collapseLevel = collapseLevel.prev() } }
    }

    // MARK: - Header Only

    private var headerOnlyView: some View {
        header
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { collapseLevel = collapseLevel.prev() } }
    }

    // MARK: - Full / Compact / Expanded

    private var fullView: some View {
        VStack(spacing: 0) {
            header
            tripleStatusRow
            Rectangle().fill(Ap.sep).frame(height: 1).padding(.horizontal, 12)
            if collapseLevel == .expanded {
                statusSection
                Rectangle().fill(Ap.sep).frame(height: 1).padding(.horizontal, 12)
            }
            if collapseLevel != .compact {
                modeBar
            }
            canvas.frame(height: canvasHeight)
            if collapseLevel == .expanded {
                logs
            }
            dock
        }
    }

    private var canvasHeight: CGFloat {
        switch collapseLevel {
        case .expanded: return 110
        case .compact:  return 140
        default:        return 100
        }
    }

    // Three icons side-by-side, same glassRow + circle-icon pattern as statusRow
    private var tripleStatusRow: some View {
        HStack(spacing: 8) {
            tripleStatusBtn("mic.fill",    color: .green,                              active: micOn)          { micOn.toggle() }
            tripleStatusBtn("brain",       color: Color(red: 0.25, green: 0.55, blue: 1.0), active: appState.isDeducing) { analysisOn.toggle() }
            tripleStatusBtn("chevron.left.forwardslash.chevron.right",
                            color: Color(red: 0.58, green: 0.2, blue: 0.92),
                            active: appState.isExecuting) { codeOn.toggle() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func tripleStatusBtn(_ icon: String, color: Color, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(active ? color : Ap.iconFaint)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background { glassRow(on: active, color: color, active: active, cornerRadius: 10) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var shell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.52))
            LinearGradient(colors: [Ap.spec.opacity(Ap.specOp * 0.80), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.22), Color(red: 0.08, green: 0.08, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    LogoImage(size: 16)
                }.frame(width: 24, height: 24)
                Text("autoclaw").font(.system(size: 12, weight: .semibold)).foregroundColor(Ap.textPrimary).kerning(-0.4)
            }
            Spacer()
            if collapseLevel != .expanded {
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        collapseLevel = collapseLevel.prev()
                    }
                } label: {
                    Circle().fill(Ap.iconBg).frame(width: 20, height: 20)
                        .overlay(Image(systemName: "plus").font(.system(size: 8, weight: .medium)).foregroundColor(Ap.textTertiary))
                }.buttonStyle(.plain)
            }
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    collapseLevel = collapseLevel.next()
                }
            } label: {
                Circle().fill(Ap.iconBg).frame(width: 20, height: 20)
                    .overlay(Image(systemName: "minus").font(.system(size: 8, weight: .medium)).foregroundColor(Ap.textTertiary))
            }.buttonStyle(.plain)
        }.padding(.horizontal, 14).frame(height: 40)
    }

    // MARK: - Status (3 full rows: mic, analysis, execution)

    private var statusSection: some View {
        VStack(spacing: 6) {
            statusRow(icon: "mic.fill", color: .green,
                      title: nil, sub: micOn ? "Apple SF · LOCAL" : "Paused · tap to resume",
                      enabled: micOn, active: micOn, waveform: true) { micOn.toggle() }
            statusRow(icon: "brain", color: Color(red: 0.25, green: 0.55, blue: 1.0),
                      title: "Analysis", sub: analysisOn ? (appState.isDeducing ? "Haiku 4.5 · API" : "Ready") : "Off",
                      enabled: analysisOn, active: appState.isDeducing, waveform: false) { analysisOn.toggle() }
            statusRow(icon: "chevron.left.forwardslash.chevron.right", color: Color(red: 0.58, green: 0.2, blue: 0.92),
                      title: "Execution", sub: codeOn ? (appState.isExecuting ? "Running…" : "Ready") : "Off",
                      enabled: codeOn, active: appState.isExecuting, waveform: false) { codeOn.toggle() }
        }.padding(.horizontal, 10).padding(.bottom, 6)
    }

    private func statusRow(icon: String, color: Color, title: String?, sub: String,
                            enabled: Bool, active: Bool, waveform: Bool, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Ap.iconBg).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(active ? color : (enabled ? color.opacity(0.82) : Ap.iconFaint))
            }
            VStack(alignment: .leading, spacing: waveform ? 2 : 1) {
                if waveform { waveformView(on: active, color: color) }
                else if let t = title {
                    Text(t).font(.system(size: 11, weight: .semibold))
                        .foregroundColor(active ? Ap.textPrimary : (enabled ? Ap.textSecondary : Ap.textOff))
                }
                Text(sub).font(.system(size: waveform ? 8 : 9, weight: .medium))
                    .foregroundColor(active ? Ap.textSecondary : (enabled ? Ap.textTertiary : Ap.textOff.opacity(0.6)))
            }
            Spacer()
            Circle().fill(active ? color.opacity(0.90) : (enabled ? color.opacity(0.65) : Ap.dotOff)).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity).frame(height: 48)
        .background { glassRow(on: enabled || active, color: color, active: active) }
        .intelligenceGlow(color: color, cornerRadius: 16, state: active ? .thinking : (enabled ? .enabled : .off))
        .contentShape(Rectangle()).onTapGesture { onTap() }
    }

    private func waveformView(on: Bool, color: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(on ? color : Ap.iconOff)
                    .frame(width: 2.5, height: on ? CGFloat.random(in: 3...16) : 3)
            }
        }.frame(height: 20)
    }

    // MARK: - Mode Bar

    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(PillMode.allCases, id: \.self) { mode in
                Button {
                    pillMode = mode
                    // Wire PillMode.learn to RequestMode.learn
                    if mode == .learn {
                        appState.requestMode = .learn
                        appState.showThread = true
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(pillMode == mode ? (mode == .learn && appState.isLearnRecording ? Color.yellow : Ap.textPrimary) : Ap.modeOff)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(pillMode == mode ? (mode == .learn && appState.isLearnRecording ? Color.yellow.opacity(0.15) : Ap.modeBgAct) : .clear)
                            .overlay(pillMode == mode ? RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(mode == .learn && appState.isLearnRecording ? Color.yellow.opacity(0.4) : Ap.modeBorderAct, lineWidth: 1) : nil))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 12).padding(.vertical, 3).frame(height: 34)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack { canvasContent }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ap.canvasBg)
                LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ap.borderOff.opacity(0.5), lineWidth: 0.8)
            } }
            .overlay {
                if appState.isExecuting { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.purple.opacity(0.4), lineWidth: 1.5).shadow(color: .purple.opacity(0.3), radius: 8) }
                else if appState.isDeducing { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.cyan.opacity(0.4), lineWidth: 1.5).shadow(color: .cyan.opacity(0.3), radius: 6) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12).padding(.bottom, 6)
    }

    @ViewBuilder private var canvasContent: some View {
        // Canvas is status-only — details appear in toasts
        VStack(spacing: 6) {
            // State indicator
            statusIndicator

            // Status line from AppState
            Text(appState.statusLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.2), value: appState.statusLine)

            // Learn mode: recording info
            if appState.isLearnRecording {
                HStack(spacing: 5) {
                    Circle().fill(Color.yellow).frame(width: 6, height: 6)
                    Text("\(appState.workflowRecorder.events.count) events")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("·")
                        .foregroundColor(Ap.textDim)
                    Text(appState.workflowRecorder.elapsedFormatted)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.5))
                }
            }

            // Spinner when working
            if appState.isDeducing || appState.isExecuting {
                ProgressView().scaleEffect(0.6)
            }

            // Brief context line
            if appState.isExecuting, !appState.executionOutput.isEmpty {
                Text(String(appState.executionOutput.suffix(50)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7))
                    .lineLimit(2)
            } else if appState.currentSuggestion != nil || appState.pendingClarification != nil || appState.deductionError != nil {
                Text("See toast").font(.system(size: 9)).foregroundColor(Ap.textDim)
            }

            // Project chips when needed
            if !appState.sessionActive || appState.needsProjectSelection {
                pChips
            } else if let p = appState.selectedProject {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill").font(.system(size: 9)).foregroundColor(Ap.textTertiary)
                    Text(p.name).font(.system(size: 10, weight: .medium)).foregroundColor(Ap.textSecondary)
                }
            }

            // Thread info
            if let thread = appState.currentThread, thread.taskCount > 0 {
                Text("\(thread.taskCount) tasks in session")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Ap.textDim)
            }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIndicator: some View {
        Group {
            if appState.isVoiceListening {
                lbl("VOICE", icon: "mic.fill", c: .red)
            } else if appState.isLearnRecording {
                lbl("RECORDING", icon: "eye.fill", c: .yellow)
            } else if appState.isExtractingSteps {
                lbl("EXTRACTING", icon: "sparkles", c: .yellow)
            } else if appState.isExecuting {
                lbl("EXECUTING", icon: "chevron.left.forwardslash.chevron.right", c: .purple)
            } else if appState.isDeducing {
                lbl("ANALYZING", icon: "sparkles", c: .cyan)
            } else if appState.deductionError != nil {
                lbl("ERROR", icon: "exclamationmark.triangle", c: .red)
            } else if appState.pendingClarification != nil {
                lbl("QUESTION", icon: "questionmark.circle", c: .purple)
            } else if appState.currentSuggestion != nil {
                lbl("READY", icon: "sparkles", c: .green)
            } else if appState.needsProjectSelection {
                lbl("PROJECT", icon: "folder", c: .orange)
            } else if appState.sessionActive {
                lbl("LISTENING", icon: "doc.on.clipboard", c: .cyan)
            } else {
                Circle().fill(Ap.dotOff.opacity(0.7)).frame(width: 8, height: 8)
            }
        }
    }

    private var statusColor: Color {
        if appState.isVoiceListening { return .red.opacity(0.8) }
        if appState.isLearnRecording { return .yellow.opacity(0.8) }
        if appState.isExtractingSteps { return .yellow.opacity(0.7) }
        if appState.deductionError != nil { return .red.opacity(0.7) }
        if appState.isExecuting { return .purple.opacity(0.8) }
        if appState.isDeducing { return .cyan.opacity(0.7) }
        if appState.currentSuggestion != nil { return .green.opacity(0.8) }
        if appState.needsProjectSelection { return .orange.opacity(0.8) }
        if appState.sessionActive { return Ap.textSecondary }
        return Ap.textDim
    }

    // MARK: - Project Chips

    private var pChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROJECT").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Ap.textTertiary).tracking(1)
            FlowLayout(spacing: 5) {
                pChip("None", i: 0, sel: appState.selectedProject == nil) { appState.selectedProject = nil }
                ForEach(Array(appState.projectStore.projects.enumerated()), id: \.element.id) { i, p in
                    pChip(p.name, i: i + 1, sel: appState.selectedProject?.id == p.id) {
                        if appState.needsProjectSelection { appState.projectSelectedAfterClipboard(p) }
                        else { appState.selectedProject = p }
                    }
                }
            }
        }
    }

    private func pChip(_ name: String, i: Int, sel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("\(i)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(sel ? .white.opacity(0.7) : Ap.textTertiary)
                Text(name).font(.system(size: 11, weight: sel ? .semibold : .regular)).foregroundColor(sel ? .white : Ap.textSecondary)
            }.padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sel ? Color.cyan.opacity(0.45) : Ap.rowTile.opacity(Ap.rowOff)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(sel ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1))
                .shadow(color: sel ? Color.cyan.opacity(0.3) : .clear, radius: 4)
        }.buttonStyle(.plain)
    }

    // MARK: - Logs

    private var logs: some View {
        VStack(spacing: 5) {
            logBar(dot: appState.sessionActive ? .green : Color(hex: "818CF8"),
                   text: appState.isExecuting ? "Code execution enabled" : (appState.sessionActive ? "Session active" : "Pipeline idle"),
                   time: ts())
            logBar(dot: .white.opacity(0.3),
                   text: !appState.activeApp.isEmpty ? String(("\(appState.activeApp): \(appState.activeWindowTitle)").prefix(28)) + "…" : "Ready",
                   time: ts())
        }.padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
    }

    private func logBar(dot: Color, text: String, time: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 4, height: 4)
            Text(text).font(.system(size: 9)).foregroundColor(Ap.textSecondary).lineLimit(1)
            Spacer()
            Text(time).font(.system(size: 8)).foregroundColor(Ap.textTertiary)
        }.padding(.horizontal, 10).padding(.vertical, 5).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Ap.logBg))
    }

    // MARK: - Dock (play/pause/stop | camera | screen share)

    private var dock: some View {
        HStack(spacing: 0) {
            if appState.sessionActive {
                if appState.sessionPaused {
                    dockBtn("play.fill", on: true, c: Color(red: 0.2, green: 0.78, blue: 0.44)) { appState.togglePause() }
                } else {
                    dockBtn("pause.fill", on: true, c: Color(red: 0.95, green: 0.75, blue: 0.1)) { appState.togglePause() }
                }
                dockBtn("stop.fill", on: true, c: Color(red: 0.92, green: 0.26, blue: 0.24)) { appState.endSession() }
            } else {
                dockBtn("play.fill", on: false, c: Color(red: 0.2, green: 0.78, blue: 0.44)) { appState.toggleSession() }
            }
            Rectangle().fill(Ap.dockSep).frame(width: 1, height: 20)
            dockBtn("camera.fill", on: false, c: Color(red: 0.0, green: 0.78, blue: 0.9)) { appState.addScreenshotToThread() }
            Rectangle().fill(Ap.dockSep).frame(width: 1, height: 20)
            dockBtn(screenShareOn ? "tv.fill" : "tv", on: screenShareOn, c: Color(red: 0.0, green: 0.78, blue: 0.9)) { screenShareOn.toggle() }
        }.frame(height: 38).padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func dockBtn(_ icon: String, on: Bool, c: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundColor(on ? c : Ap.textOff)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? c.opacity(0.14) : .clear)
                    .overlay(on ? RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(c.opacity(0.28), lineWidth: 1) : nil))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func glassRow(on: Bool, color: Color, active: Bool = false, cornerRadius: CGFloat = 16) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Ap.rowTile.opacity(active ? Ap.rowAct : (on ? Ap.rowOn : Ap.rowOff)))
            if on { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(LinearGradient(colors: [color.opacity(active ? 0.20 : 0.10), color.opacity(active ? 0.08 : 0.04)], startPoint: .top, endPoint: .bottom)) }
            LinearGradient(colors: [Ap.spec.opacity(Ap.specOp), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)).clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(LinearGradient(colors: [on ? color.opacity(active ? 0.42 : 0.24) : Ap.borderOff, on ? color.opacity(active ? 0.08 : 0.06) : Ap.borderLow], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
    }

    private func lbl(_ t: String, icon: String, c: Color) -> some View {
        HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 9)).foregroundColor(c); Text(t).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(c).tracking(1) }
    }

    private func cBtn(_ t: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(t).font(.system(size: 9, weight: .bold)).foregroundColor(fg).padding(.horizontal, 10).padding(.vertical, 4).background(bg).cornerRadius(6) }.buttonStyle(.plain)
    }

    private func ts() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date()) }
}

// MARK: - Intelligence Glow

private struct EnabledGlow: View {
    let color: Color; let cornerRadius: CGFloat
    @State private var opacity: Double = 0.15
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color.opacity(opacity), lineWidth: 1.5).blur(radius: 3).allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 6, style: .continuous))
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
