import SwiftUI

// MARK: - Request Mode

enum RequestMode: String, CaseIterable, Identifiable {
    case task = "Task"
    case addToTasks = "Add to Tasks"
    case question = "Question"
    case analyze = "Analyze"
    case learn = "Learn"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .task:       return "play.fill"
        case .addToTasks: return "plus.circle"
        case .question:   return "questionmark.bubble"
        case .analyze:    return "sparkle.magnifyingglass"
        case .learn:      return "eye.fill"
        }
    }

    var color: Color {
        switch self {
        case .task:       return .green
        case .addToTasks: return .orange
        case .question:   return .purple
        case .analyze:    return .cyan
        case .learn:      return .yellow
        }
    }

    var placeholder: String {
        switch self {
        case .task:       return "Describe the task…"
        case .addToTasks: return "What should be added?"
        case .question:   return "Ask a question…"
        case .analyze:    return "What should I analyze?"
        case .learn:      return "Tap record to learn a workflow…"
        }
    }
}

// MARK: - Thread Toast View (the session chat thread)

struct ThreadToastView: View {
    @ObservedObject var appState: AppState
    var onApprove: () -> Void
    var onDirectExecute: () -> Void
    var onDismiss: () -> Void
    var onResume: (() -> Void)?

    @State private var inputText = ""
    @State private var expandedMessages: Set<UUID> = []

    /// Whether the toast is showing a "session ended" state
    private var isSessionEnded: Bool {
        !appState.sessionActive && !appState.threadMessages.isEmpty
    }

    private var glowState: GlowState {
        if isSessionEnded { return .off }
        if appState.isExecuting || appState.isDeducing { return .thinking }
        if appState.sessionActive && appState.sessionPaused { return .enabled }
        if appState.sessionActive { return .enabled }
        return .off
    }

    private var glowColor: Color {
        if appState.isExecuting || appState.isDeducing { return .purple }
        if appState.sessionActive && appState.sessionPaused { return .white }
        if appState.sessionActive {
            // Check if last message was successful execution
            if case .execution = appState.threadMessages.last { return .cyan }
            return .green
        }
        return .clear
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            threadHeader

            Divider().opacity(0.15)

            // Thread messages
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        // Collapse older messages if many
                        if appState.threadMessages.count > 4 {
                            collapsedOlderSection
                        }

                        ForEach(visibleMessages) { msg in
                            threadMessageView(msg)
                                .id(msg.id)
                        }

                        // Voice Mode: live transcription bar
                        if appState.isVoiceListening {
                            voiceListeningBar
                        }

                        // Learn Mode: recording bar
                        if appState.isLearnRecording {
                            learnRecordingBar
                        }

                        // Learn Mode: extracting steps indicator
                        if appState.isExtractingSteps {
                            extractingStepsView
                        }

                        // Learn Mode: save workflow card (after extraction)
                        if appState.currentRecording != nil && !appState.extractedSteps.isEmpty && !appState.isExtractingSteps {
                            saveWorkflowCard
                        }

                        if appState.isDeducing {
                            thinkingIndicator
                        }

                        // Live execution output
                        if appState.isExecuting || (!appState.executionOutput.isEmpty && !hasExecutionMessage) {
                            liveExecutionView
                                .id("live-exec")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
                .onChange(of: appState.threadMessages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: appState.executionOutput) { _ in
                    if appState.isExecuting {
                        scrollToBottom(proxy)
                    }
                }
            }

            Divider().opacity(0.15)

            // Input bar or session-ended bar
            if isSessionEnded {
                sessionEndedBar
            } else {
                inputBar
            }
        }
        .frame(width: 320)
        .intelligenceGlow(color: glowColor, cornerRadius: 12, state: glowState)
        .onChange(of: appState.pendingVoiceText) { newText in
            // Populate input field with voice transcript for user to review/edit/send
            if !newText.isEmpty {
                if inputText.isEmpty {
                    inputText = newText
                } else {
                    inputText += " " + newText
                }
                appState.pendingVoiceText = ""
            }
        }
    }

    // MARK: - Session State

    private var sessionStateColor: Color {
        if isSessionEnded { return .secondary }
        if appState.isExecuting || appState.isDeducing { return .purple }
        if appState.sessionPaused { return .white.opacity(0.6) }
        if case .execution = appState.threadMessages.last { return .cyan }
        return .green
    }

    // MARK: - Header

    private var threadHeader: some View {
        VStack(spacing: 0) {
            // Top row: menubar icon + title + message count + close
            HStack(alignment: .center, spacing: 5) {
                // Menubar icon — tinted to match session state
                MenuBarIconView(color: sessionStateColor, size: 14)

                Text("autoclaw")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSessionEnded ? .secondary : .primary)

                Spacer()

                if appState.isDeducing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }

                Text("\(appState.threadMessages.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Bottom row: model picker + project picker + request mode
            HStack(spacing: 4) {
                modelPicker
                projectPicker
                Spacer()
                requestModeCapsule
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Model Picker

    private var modelPicker: some View {
        Menu {
            ForEach(ClaudeModel.allCases) { model in
                Button {
                    appState.selectedModel = model
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model == appState.selectedModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 7))
                Text(appState.selectedModel.displayName)
                    .font(.system(size: 9, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.cyan.opacity(0.12))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Project Picker

    private var projectPicker: some View {
        Menu {
            ForEach(appState.projectStore.projects) { project in
                Button {
                    appState.selectedProject = project
                    // Reassign current thread if needed
                    if let thread = appState.currentThread {
                        appState.sessionStore.reassignProject(id: thread.id, projectId: project.id)
                    }
                } label: {
                    HStack {
                        Text(project.name)
                        if project.id == appState.selectedProject?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if appState.projectStore.projects.isEmpty {
                Text("No projects — add in Settings")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 7))
                Text(appState.selectedProject?.name ?? "No project")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(appState.selectedProject != nil ? .orange : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((appState.selectedProject != nil ? Color.orange : Color.gray).opacity(0.12))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Visible Messages

    private var visibleMessages: [ThreadMessage] {
        if appState.threadMessages.count <= 4 {
            return appState.threadMessages
        }
        // Show last 4 messages, older ones are in collapsed section
        return Array(appState.threadMessages.suffix(4))
    }

    private var collapsedOlderSection: some View {
        let hiddenCount = appState.threadMessages.count - 4
        return Button {
            // Could expand in future; for now just a label
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(hiddenCount) earlier")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.tertiary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Views

    @ViewBuilder
    private func threadMessageView(_ msg: ThreadMessage) -> some View {
        switch msg {
        case .clipboard(let id, let content, let app, let window, _):
            clipboardBubble(id: id, content: content, app: app, window: window)
        case .screenshot(_, let path, _):
            screenshotChip(path: path)
        case .userMessage(_, let text, _):
            userMessageBubble(text: text)
        case .haiku(_, let suggestion, _):
            haikuResponseCard(suggestion: suggestion)
        case .execution(_, let output, _):
            executionCard(output: output)
        case .error(_, let message, _):
            errorCard(message: message)
        case .context(_, let app, let window, _):
            contextChips(app: app, window: window)
        case .attachment(_, _, let name, let size, _):
            attachmentChip(name: name, size: size)
        case .learnEvent(_, let event, _):
            learnEventRow(event)
        case .workflowSaved(_, let workflow, _):
            workflowSavedRow(workflow)
        case .frictionOffer(_, let signal, _):
            frictionOfferCard(signal)
        }
    }

    private func frictionOfferCard(_ signal: FrictionDetector.FrictionSignal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(.yellow)
                Text("ARIA").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                Spacer()
                Text(signal.involvedApps.joined(separator: " → "))
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            Text(signal.suggestion)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                if signal.isActionable {
                    Button("Do it") { appState.acceptFrictionOffer(signal) }
                        .buttonStyle(.borderedProminent).tint(.yellow).controlSize(.mini)
                } else {
                    Button("Find integration") { appState.discoverCapability(for: signal) }
                        .buttonStyle(.borderedProminent).tint(.blue).controlSize(.mini)
                }
                Button("Dismiss") { appState.dismissFriction() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func clipboardBubble(id: UUID, content: String, app: String, window: String) -> some View {
        let isExpanded = expandedMessages.contains(id)
        let preview = String(content.prefix(120))
        let isTruncated = content.count > 120

        return VStack(alignment: .leading, spacing: 4) {
            // Header row: app chip + copy button
            HStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 8))
                if !app.isEmpty { Text(app).font(.system(size: 9)) }
                if !window.isEmpty {
                    Text("·").font(.system(size: 8)).foregroundStyle(.quaternary)
                    Text(window).font(.system(size: 9)).lineLimit(1)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .foregroundStyle(.secondary)

            // Content
            Text(isExpanded ? content : preview + (isTruncated ? "…" : ""))
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if isTruncated {
                Button(isExpanded ? "Show less" : "Show more") {
                    if isExpanded { expandedMessages.remove(id) } else { expandedMessages.insert(id) }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func contextChips(app: String, window: String) -> some View {
        HStack(spacing: 4) {
            // App chip
            if !app.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 7))
                    Text(app)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }

            // Window chip
            if !window.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 7))
                    Text(window)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.10))
                .clipShape(Capsule())
            }

            Spacer()
        }
    }

    private func screenshotChip(path: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "camera.fill")
                .font(.system(size: 7))
            Text("Screenshot")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                Text("· \(ThreadMessage.formatSize(size))")
                    .font(.system(size: 8))
                    .foregroundStyle(.green.opacity(0.7))
            }
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
    }

    private func attachmentChip(name: String, size: Int64) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ThreadMessage.iconForFile(name))
                .font(.system(size: 7))
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
            Text("· \(ThreadMessage.formatSize(size))")
                .font(.system(size: 8))
                .foregroundStyle(.purple.opacity(0.7))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.10))
        .clipShape(Capsule())
    }

    private func userMessageBubble(text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func haikuResponseCard(suggestion: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch suggestion.kind {
            case .clarification:
                clarificationCard(suggestion.clarification!)

            case .execute:
                executeCard(suggestion)

            case .draft:
                draftOrAnswerCard(suggestion, accentColor: .green, badge: "Draft ready", icon: "doc.text.fill")

            case .answer:
                draftOrAnswerCard(suggestion, accentColor: .cyan, badge: "Answer", icon: "sparkles")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func clarificationCard(_ clarification: Clarification) -> some View {
        Label("Needs info", systemImage: "questionmark.circle.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.purple)

        Text(clarification.question)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(3)

        if let ctx = clarification.context {
            Text(ctx)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }

        if let options = clarification.options, !options.isEmpty {
            VStack(spacing: 3) {
                ForEach(options, id: \.self) { option in
                    Button {
                        appState.respondToClarification(option)
                    } label: {
                        HStack {
                            Text(option).font(.system(size: 10)).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.quaternary)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func executeCard(_ suggestion: TaskSuggestion) -> some View {
        // Skill chain + confidence
        if !suggestion.skills.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(suggestion.skills.enumerated()), id: \.offset) { index, skill in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 6, weight: .bold)).foregroundStyle(.quaternary)
                    }
                    Text(skill)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        Text(suggestion.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(2)

        Text(suggestion.draft)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(3)

        if let plan = suggestion.completionPlan {
            Text(plan)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }

        HStack(spacing: 6) {
            Button("Run", action: onApprove)
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            Button("Skip") { appState.dismissSuggestion() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func draftOrAnswerCard(_ suggestion: TaskSuggestion, accentColor: Color, badge: String, icon: String) -> some View {
        // Badge row
        HStack {
            Label(badge, systemImage: icon)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(accentColor)
            Spacer()
            Text("\(Int(suggestion.confidence * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }

        Text(suggestion.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(2)

        // The actual draft/answer text — selectable
        Text(suggestion.draft)
            .font(.system(size: 10))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(6)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        // CTA row: Copy + Dismiss
        HStack(spacing: 6) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(suggestion.draft, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(accentColor)

            Button("Dismiss") { appState.dismissSuggestion() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func executionCard(output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.green)

            Text(String(output.suffix(200)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Button("Retry") {
                appState.sendToHaiku()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(.red)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
            Text("Analyzing…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Whether the thread already has a .execution message (so we don't show live + final)
    private var hasExecutionMessage: Bool {
        appState.threadMessages.contains { if case .execution = $0 { return true }; return false }
    }

    private var liveExecutionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if appState.isExecuting {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text("Executing…")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text("Done")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            if !appState.executionOutput.isEmpty {
                Text(String(appState.executionOutput.suffix(300)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((appState.isExecuting ? Color.orange : Color.green).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if appState.isExecuting {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("live-exec", anchor: .bottom) }
        } else if let last = appState.threadMessages.last {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Input Bar

    // MARK: - Request Mode Capsule (in header, clickable to cycle)

    private var requestModeCapsule: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.cycleRequestMode()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: appState.requestMode.icon)
                    .font(.system(size: 7))
                Text(appState.requestMode.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(appState.requestMode.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(appState.requestMode.color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Cycle mode (⌥X)")
    }

    private var inputBar: some View {
        Group {
            if appState.requestMode == .learn {
                learnInputBar
            } else {
                standardInputBar
            }
        }
    }

    private var standardInputBar: some View {
        HStack(spacing: 6) {
            // Screenshot button
            Button {
                appState.addScreenshotToThread()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Capture screenshot (⌥Z)")

            // Text input — placeholder matches the current mode
            TextField(appState.requestMode.placeholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit {
                    submitForMode()
                }

            // Submit button — icon and color match the mode
            Button {
                submitForMode()
            } label: {
                Image(systemName: appState.requestMode.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(canSend ? appState.requestMode.color : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send (\(appState.requestMode.rawValue))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var learnInputBar: some View {
        HStack(spacing: 8) {
            if appState.isLearnRecording {
                // Recording — show stop + discard
                Button {
                    appState.stopLearnRecording()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop + save")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    appState.discardLearnRecording()
                } label: {
                    Text("Discard")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                // Not recording — show start button
                Button {
                    appState.startLearnRecording()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Start recording")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Record your workflow to automate it")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Session Ended Bar

    private var sessionEndedBar: some View {
        HStack(spacing: 8) {
            Text("Session ended")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if let resume = onResume {
                Button {
                    resume()
                } label: {
                    Label("Resume", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty || hasContext
    }

    private var hasContext: Bool {
        appState.threadMessages.contains { msg in
            switch msg {
            case .clipboard, .screenshot, .attachment: return true
            default: return false
            }
        }
    }

    private func submitForMode() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        inputText = ""

        switch appState.requestMode {
        case .task:
            // Direct execute — skip deduction
            onDirectExecute()
            if text.isEmpty { appState.directExecute() }
            else { appState.directExecuteMessage(text) }

        case .addToTasks:
            // Wrap as a "create ClickUp task" instruction
            let taskText = text.isEmpty ? "Create a task from the clipboard context" : text
            let prompt = "Create a ClickUp task for this: \(taskText)"
            onDirectExecute()
            appState.directExecuteMessage(prompt)

        case .question:
            // Ask a question about the project — direct execute with question framing
            let questionText = text.isEmpty ? "Answer the question based on the context" : text
            let prompt = "Answer this question about the project: \(questionText)"
            onDirectExecute()
            appState.directExecuteMessage(prompt)

        case .analyze:
            // Deduce first via Haiku
            if text.isEmpty { appState.sendToHaiku() }
            else { appState.sendMessage(text) }

        case .learn:
            // Toggle recording
            if appState.isLearnRecording {
                appState.stopLearnRecording()
            } else {
                appState.startLearnRecording()
            }
        }
    }

    // MARK: - Voice Mode

    private var voiceListeningBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Pulsing red mic dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(voicePulse ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voicePulse)
                    .onAppear { voicePulse = true }
                    .onDisappear { voicePulse = false }

                Text("voice")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)

                Spacer()

                Button {
                    appState.toggleVoice()
                } label: {
                    Text("stop")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }

            // Live transcript preview
            if !appState.liveTranscript.isEmpty {
                Text(appState.liveTranscript)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Listening…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    @State private var voicePulse = false

    // MARK: - Learn Mode Recording Bar

    private var learnRecordingBar: some View {
        HStack(spacing: 8) {
            // Pulsing amber dot
            Circle()
                .fill(Color.yellow)
                .frame(width: 7, height: 7)
                .opacity(recordingPulse ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingPulse)
                .onAppear { recordingPulse = true }
                .onDisappear { recordingPulse = false }

            Text("recording workflow")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)

            Spacer()

            Text(appState.workflowRecorder.elapsedFormatted)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.yellow.opacity(0.45))

            Button {
                appState.stopLearnRecording()
            } label: {
                Text("stop")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    @State private var recordingPulse = false

    // MARK: - Learn Event Row

    private func learnEventRow(_ event: WorkflowEvent) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(event.elapsedFormatted)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 32, alignment: .leading)

            Circle()
                .fill(event.type == .clipboard ? Color.yellow : event.type == .click ? Color.cyan : Color.white.opacity(0.14))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            Text(event.description)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            if !event.app.isEmpty {
                Text(event.app)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Save Workflow Card

    private var saveWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Text("\(appState.extractedSteps.count) steps extracted")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Spacer()

                Text("save workflow?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            // Description
            Text("Name and save to run again in one tap")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Step list
            VStack(spacing: 0) {
                ForEach(appState.extractedSteps) { step in
                    HStack(spacing: 8) {
                        // Step number circle
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 18, height: 18)
                            Text("\(step.index)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }

                        Text(step.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer()

                        // Tool badge
                        Text(step.tool)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(.vertical, 6)

                    if step.id != appState.extractedSteps.last?.id {
                        Divider().opacity(0.15)
                    }
                }
            }

            // Workflow name input
            TextField("Workflow name", text: $appState.workflowNameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action buttons
            HStack(spacing: 7) {
                Button {
                    appState.saveWorkflow(name: appState.workflowNameDraft)
                } label: {
                    Text("Save workflow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    // TODO: Edit steps view
                } label: {
                    Text("Edit steps")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    appState.discardLearnRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    // MARK: - Extracting Steps Indicator

    private var extractingStepsView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
            Text("Extracting workflow steps…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Workflow Saved Confirmation

    private func workflowSavedRow(_ workflow: SavedWorkflow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Workflow saved")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("\(workflow.name) — \(workflow.steps.count) steps")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(workflow.totalEstimatedFormatted)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Project Picker Toast (kept separate — pre-session)

struct ProjectPickerToastView: View {
    @ObservedObject var appState: AppState
    var onSelect: (Project) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row
            HStack(alignment: .center) {
                Label("Select project", systemImage: "folder.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.orange)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Headline
            Text("Clipboard captured")
                .font(.system(size: 13, weight: .semibold))

            // Clipboard preview
            if !appState.lastClipboard.isEmpty {
                Text(String(appState.lastClipboard.prefix(80)) + (appState.lastClipboard.count > 80 ? "..." : ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Project list
            ForEach(appState.projectStore.projects) { project in
                Button {
                    onSelect(project)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .font(.system(size: 11, weight: .medium))
                            Text(project.path)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if appState.projectStore.projects.isEmpty {
                Text("No projects yet — add one in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
    }
}
