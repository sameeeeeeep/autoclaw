import SwiftUI

// MARK: - Thread Toast View (the session chat thread)

struct ThreadToastView: View {
    @ObservedObject var appState: AppState
    var onApprove: () -> Void
    var onDismiss: () -> Void

    @State private var inputText = ""
    @State private var expandedMessages: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            threadHeader

            Divider().opacity(0.3)

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

                        if appState.isDeducing {
                            thinkingIndicator
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 340)
                .onChange(of: appState.threadMessages.count) { _ in
                    if let last = appState.threadMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().opacity(0.3)

            // Input bar
            inputBar
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var threadHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            LogoImage(size: 14)

            Text("autoclaw")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        }
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 6) {
            // Screenshot button
            Button {
                appState.addScreenshotToThread()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Capture screenshot")

            // Text input
            TextField("Add context or send to analyze…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit {
                    submitInput()
                }

            // Send button
            Button {
                submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(canSend ? Color.blue : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
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

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        inputText = ""
        if text.isEmpty {
            // Send with just accumulated context (blind deduction)
            appState.sendToHaiku()
        } else {
            // Send with user message
            appState.sendMessage(text)
        }
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
