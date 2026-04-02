import SwiftUI

// MARK: - Unified Toast View

/// Single adaptive toast card for all modes — replaces the cramped ThreadToastView.
/// Uses FrictionToastView's clean Cofia-style design language: 340px wide, 16px corners,
/// generous padding, clear hierarchy.
struct UnifiedToastView: View {
    @ObservedObject var appState: AppState
    var onDirectExecute: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onResume: () -> Void = {}
    // Friction callbacks
    var onAutomate: () -> Void = {}
    var onEditSteps: () -> Void = {}
    var onRun: () -> Void = {}
    var onStop: () -> Void = {}
    var onOpen: () -> Void = {}
    var onRetry: () -> Void = {}

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var addedToBoard: String?  // flash feedback
    @State private var copiedText: String?     // flash feedback for copy

    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    /// Glow color: green when user is speaking, orange when intelligence is working, off otherwise
    private var toastGlowColor: Color {
        if appState.transcribeStatus == .listening {
            return Theme.teal  // Green — user is speaking
        }
        return Theme.purple  // Orange — intelligence working
    }

    private var toastGlowState: GlowState {
        if appState.transcribeStatus == .listening {
            return .thinking  // Pulsing green while mic is on
        }
        if appState.transcribeService.isGeneratingPrompt || appState.transcribeService.isEnhancing {
            return .thinking  // Pulsing orange while AI is working
        }
        return .off
    }

    var body: some View {
        VStack(spacing: 0) {
            cardContent
        }
        .frame(width: 420)
        .modifier(LiquidGlassBackground(fallbackColor: theme.card))
        .intelligenceGlow(
            color: toastGlowColor,
            cornerRadius: 16,
            state: toastGlowState
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 24, y: 8)
    }

    // MARK: - Mode Router

    @ViewBuilder
    private var cardContent: some View {
        switch appState.requestMode {
        case .task:
            taskCardView
        case .analyze:
            analyzeCardView
        case .learn:
            learnCardView
        case .transcribe:
            transcribeCardView
        }
    }

    // MARK: - Task Card

    @ViewBuilder
    private var taskCardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            toastHeader(
                icon: appState.requestMode.icon,
                title: appState.requestMode.rawValue,
                color: appState.requestMode.color
            )

            // Context — what triggered this
            if !appState.lastClipboard.isEmpty {
                contextChip(
                    icon: "doc.on.clipboard",
                    text: String(appState.lastClipboard.prefix(120)),
                    app: appState.clipboardCapturedApp
                )
            }

            // State-dependent content
            if appState.isDeducing {
                executingIndicator(label: "Thinking…", color: Theme.purple)
            } else if appState.isExecuting {
                executingIndicator(label: "Working on it…", color: Theme.blue)

                // Live output preview
                if !appState.executionOutput.isEmpty {
                    Text(String(appState.executionOutput.suffix(200)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(4)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if !appState.executionOutput.isEmpty && !appState.isExecuting {
                // Result
                resultCard(
                    text: String(appState.executionOutput.prefix(300)),
                    color: Theme.green,
                    icon: "checkmark.circle.fill"
                )
            } else if let error = appState.deductionError {
                // Error
                resultCard(text: error, color: Theme.red, icon: "exclamationmark.triangle.fill")
            } else if !appState.sessionActive {
                // Session ended
                VStack(spacing: 8) {
                    Text("Session ended")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    actionButton(title: "New Session", icon: "plus", action: onResume)
                }
            } else {
                // Input bar
                taskInputBar
            }
        }
        .padding(22)
    }

    // MARK: - Analyze Card

    @ViewBuilder
    private var analyzeCardView: some View {
        if let state = appState.frictionToastState {
            // Delegate to existing FrictionToastView states
            FrictionToastView(
                state: state,
                onAutomate: onAutomate,
                onEditSteps: onEditSteps,
                onRun: onRun,
                onStop: onStop,
                onOpen: onOpen,
                onRetry: onRetry,
                onDismiss: onDismiss
            )
        } else {
            // Idle analyze state
            VStack(alignment: .leading, spacing: 14) {
                toastHeader(icon: "sparkle.magnifyingglass", title: "Analyze", color: .cyan)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(.cyan)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watching your workflow…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("autoclaw will suggest automations")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                // Still allow manual input in analyze
                taskInputBar
            }
            .padding(22)
        }
    }

    // MARK: - Learn Card

    @ViewBuilder
    private var learnCardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            toastHeader(icon: "eye.fill", title: "Learn", color: .yellow)

            if appState.isExtractingSteps {
                // Extracting
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing workflow…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }
            } else if !appState.extractedSteps.isEmpty {
                // Review extracted steps
                Text("Extracted workflow steps")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                stepList(appState.extractedSteps)

                // Name field
                TextField("Workflow name…", text: Binding(
                    get: { appState.workflowNameDraft },
                    set: { appState.workflowNameDraft = $0 }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .padding(10)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                actionButton(title: "Save Workflow", icon: "square.and.arrow.down") {
                    appState.saveWorkflow(name: appState.workflowNameDraft)
                }
            } else if appState.isLearnRecording {
                // Recording
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 10, height: 10)
                        .opacity(recordingPulse ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: recordingPulse)
                        .onAppear { recordingPulse = true }

                    Text("Recording…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.red)

                    Spacer()

                    Text("\(appState.workflowRecorder.events.count) events")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }

                actionButton(title: "Stop Recording", icon: "stop.fill", color: Theme.red) {
                    appState.stopLearnRecording()
                }
            } else {
                // Ready
                VStack(spacing: 8) {
                    Text("Record a workflow for autoclaw to learn and replay.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    actionButton(title: "Start Recording", icon: "record.circle") {
                        appState.startLearnRecording()
                    }
                }
            }
        }
        .padding(22)
    }

    @State private var recordingPulse = false

    // MARK: - Transcribe Card

    @ViewBuilder
    private var transcribeCardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            toastHeader(icon: "waveform", title: "Transcribe", color: Theme.teal)

            switch appState.transcribeStatus {
            case .idle:
                // Pre-prompt suggestions — tap to inject at cursor, right-click to add to board
                if !appState.transcribeService.suggestedPrompts.isEmpty {
                    suggestedPromptsView(muted: false)
                }

                Text("Press Fn to start transcribing")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)

            case .listening:
                // Waveform — no live transcript, just recording indicator
                HStack(spacing: 8) {
                    waveformBars
                    Text("Listening… press Fn to stop")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.teal)
                }

                // Suggestions visible but muted while listening
                if !appState.transcribeService.suggestedPrompts.isEmpty {
                    suggestedPromptsView(muted: true)
                } else {
                    Text("Speak naturally. Text will appear when you stop.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                }

            case .transcribing:
                executingIndicator(label: "Transcribing...", color: Theme.teal)

            case .cleaning:
                executingIndicator(label: "Cleaning up text...", color: Theme.teal)

            case .injecting:
                executingIndicator(label: "Typing at cursor...", color: Theme.teal)

            case .done:
                // What was injected — tap to copy, right-click to add to board
                resultCard(
                    text: appState.transcribeCleanText.isEmpty ? "Done" : appState.transcribeCleanText,
                    color: copiedText == appState.transcribeCleanText ? Theme.teal : Theme.green,
                    icon: copiedText == appState.transcribeCleanText ? "doc.on.doc.fill" : "checkmark.circle.fill"
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !appState.transcribeCleanText.isEmpty else { return }
                    copyToClipboard(appState.transcribeCleanText)
                }
                .contextMenu {
                    if !appState.transcribeCleanText.isEmpty {
                        Button("Add to Board") { addToBoard(appState.transcribeCleanText) }
                        Button("Copy") { copyToClipboard(appState.transcribeCleanText) }
                    }
                }

                // Smart enhancement from Haiku
                if appState.transcribeService.isEnhancing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.purple)
                        Text("Enhancing for \(appState.activeApp.isEmpty ? "current app" : appState.activeApp)…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.purple)
                    }
                } else if !appState.transcribeService.enhancedText.isEmpty {
                    // Enhanced version — tap to inject at cursor, right-click for options
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: copiedText == appState.transcribeService.enhancedText ? "doc.on.doc.fill" : "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.purple)
                            Text(copiedText == appState.transcribeService.enhancedText ? "Copied!" : "Enhanced — tap to use")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.purple)
                        }

                        Text(appState.transcribeService.enhancedText)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.purple.opacity(colorScheme == .dark ? 0.1 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await appState.transcribeService.injectEnhanced() }
                    }
                    .contextMenu {
                        Button("Add to Board") { addToBoard(appState.transcribeService.enhancedText) }
                        Button("Copy") { copyToClipboard(appState.transcribeService.enhancedText) }
                    }
                }

                // Suggestions after done — tap to inject
                if !appState.transcribeService.suggestedPrompts.isEmpty {
                    suggestedPromptsView(muted: false)
                }

            case .error(let message):
                resultCard(text: message, color: Theme.red, icon: "exclamationmark.triangle.fill")

                Text("Press Fn to try again")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(22)
    }

    // MARK: - Shared Components

    /// Compact label for the selector
    private var selectorLabel: String {
        let projectName = appState.selectedProject?.name ?? "No project"
        if let session = appState.selectedClaudeSession {
            return "\(projectName) · \(String(session.title.prefix(20)))"
        }
        return projectName
    }

    private func sessionTimeLabel(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    private func toastHeader(icon: String, title: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())

            // Project/session selector — subtle, tappable text
            Menu {
                if !appState.projectStore.projects.isEmpty {
                    Section("Project") {
                        ForEach(appState.projectStore.projects) { project in
                            Button(action: { appState.switchToProject(project) }) {
                                HStack {
                                    Text(project.name)
                                    if project.id == appState.selectedProject?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !appState.claudeSessions.isEmpty {
                    Section("Session") {
                        ForEach(appState.claudeSessions) { session in
                            Button(action: { appState.switchToClaudeSession(session) }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.title)
                                            .lineLimit(1)
                                        Text(sessionTimeLabel(session.modifiedAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if session.id == appState.selectedClaudeSession?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Group {
                    if appState.transcribeService.isGeneratingPrompt {
                        Text(appState.selectedProject?.name ?? "reading context…")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.purple)
                            .lineLimit(1)
                    } else {
                        Text(appState.selectedProject?.name ?? "select project")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            // Feature toggles — only in Transcribe mode
            if appState.requestMode == .transcribe {
                Button(action: {
                    AppSettings.shared.suggestionsEnabled.toggle()
                    if !AppSettings.shared.suggestionsEnabled {
                        appState.transcribeService.suggestedPrompts = []
                    }
                }) {
                    Image(systemName: AppSettings.shared.suggestionsEnabled ? "lightbulb.max.fill" : "lightbulb.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(AppSettings.shared.suggestionsEnabled ? Theme.purple : theme.textMuted)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Toggle suggestions")

                Button(action: {
                    let current = AppSettings.shared.enhanceProvider
                    if current == .none {
                        AppSettings.shared.enhanceProvider = .haiku
                    } else {
                        AppSettings.shared.enhanceProvider = .none
                    }
                }) {
                    Image(systemName: AppSettings.shared.enhanceProvider != .none ? "wand.and.stars" : "wand.and.stars.inverse")
                        .font(.system(size: 11))
                        .foregroundStyle(AppSettings.shared.enhanceProvider != .none ? Theme.purple : theme.textMuted)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Toggle smart enhance")

                Button(action: {
                    AppSettings.shared.theaterMode.toggle()
                    NotificationCenter.default.post(name: .theaterModeToggled, object: nil)
                }) {
                    Image(systemName: AppSettings.shared.theaterMode ? "theatermasks.fill" : "theatermasks")
                        .font(.system(size: 11))
                        .foregroundStyle(AppSettings.shared.theaterMode ? Theme.teal : theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Toggle Theater mode")

                Button(action: {
                    NotificationCenter.default.post(name: .boardToggled, object: nil)
                }) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Toggle Board")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private func contextChip(icon: String, text: String, app: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                if !app.isEmpty {
                    Text("from \(app)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func executingIndicator(label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private func resultCard(text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(colorScheme == .dark ? 0.1 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color ?? theme.buttonBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func stepList(_ steps: [WorkflowStep]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(theme.buttonBg)
                            .frame(width: 20, height: 20)
                        Text("\(idx + 1)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.buttonText)
                    }
                    Text(step.description)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var taskInputBar: some View {
        HStack(spacing: 8) {
            TextField(appState.requestMode.placeholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .focused($inputFocused)
                .onSubmit { submitInput() }

            Button(action: submitInput) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(inputText.isEmpty ? theme.textMuted : appState.requestMode.color)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty && appState.lastClipboard.isEmpty)
        }
        .padding(10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var waveformBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.teal)
                    .frame(width: 3, height: CGFloat.random(in: 6...18))
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever()
                        .delay(Double(i) * 0.05),
                        value: appState.isTranscribing
                    )
            }
        }
        .frame(height: 18)
    }

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !appState.lastClipboard.isEmpty else { return }
        inputText = ""

        if text.isEmpty {
            appState.directExecute()
        } else {
            appState.directExecuteMessage(text)
        }
        onDirectExecute()
    }

    // MARK: - Suggested Prompts

    @ViewBuilder
    private func suggestedPromptsView(muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(appState.transcribeService.suggestedPrompts.enumerated()), id: \.offset) { idx, prompt in
                HStack(spacing: 8) {
                    Image(systemName: copiedText == prompt ? "doc.on.doc.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.purple)
                    Text(prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.purple.opacity(colorScheme == .dark ? 0.08 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.transcribeService.injectPrePrompt(at: idx)
                }
                .contextMenu {
                    Button("Add to Board") { addToBoard(prompt) }
                    Button("Copy") { copyToClipboard(prompt) }
                }
            }
        }
        .opacity(muted ? 0.4 : 1.0)
    }

    // MARK: - Board

    private func addToBoard(_ item: String) {
        guard let path = appState.selectedProject?.path else { return }
        let boardPath = "\(path)/.autoclaw/board.md"

        // Read current board
        guard var content = try? String(contentsOfFile: boardPath, encoding: .utf8) else { return }

        // Append to Todo section
        if let todoRange = content.range(of: "## Todo") {
            let insertPoint = content.index(todoRange.upperBound, offsetBy: 0)
            content.insert(contentsOf: "\n- \(item)", at: insertPoint)
        } else {
            content += "\n## Todo\n- \(item)\n"
        }

        try? content.write(toFile: boardPath, atomically: true, encoding: .utf8)

        // Flash feedback
        withAnimation(.easeOut(duration: 0.2)) { addedToBoard = item }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { addedToBoard = nil }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.2)) { copiedText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copiedText = nil }
        }
    }
}

// MARK: - Board Model

struct BoardItems {
    var todo: [String] = []
    var inProgress: [String] = []
    var done: [String] = []

    static func parse(_ content: String) -> BoardItems {
        var items = BoardItems()
        var currentSection = ""

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("## todo") {
                currentSection = "todo"
            } else if trimmed.lowercased().hasPrefix("## in progress") {
                currentSection = "inprogress"
            } else if trimmed.lowercased().hasPrefix("## done") {
                currentSection = "done"
            } else if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                    .replacingOccurrences(of: "[ ] ", with: "")
                    .replacingOccurrences(of: "[x] ", with: "")
                guard !item.isEmpty else { continue }
                switch currentSection {
                case "todo": items.todo.append(item)
                case "inprogress": items.inProgress.append(item)
                case "done": items.done.append(item)
                default: break
                }
            }
        }
        return items
    }
}

// MARK: - Liquid Glass Background

/// Applies macOS 26 liquid glass effect when available, falls back to solid background on older macOS.
private struct LiquidGlassBackground: ViewModifier {
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
