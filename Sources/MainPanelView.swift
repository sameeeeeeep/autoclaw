import SwiftUI

enum PanelTab: String, CaseIterable {
    case home = "Home"
    case threads = "Threads"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .threads: return "bubble.left.and.text.bubble.right"
        case .settings: return "gear"
        }
    }
}

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .home

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
            Divider()
            // Content
            content
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(.background)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 8) {
                LogoImage(size: 20)
                Text("autoclaw")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 12)

            // Nav items
            VStack(spacing: 2) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                        if tab != .threads { appState.viewingThread = nil }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .frame(width: 18)
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            // Session status at bottom
            if appState.sessionActive {
                VStack(spacing: 4) {
                    Divider().padding(.horizontal, 12)
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Session active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 160)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .home:
            HomeView(appState: appState)
        case .threads:
            if let thread = appState.viewingThread {
                ThreadDetailView(appState: appState, thread: thread)
            } else {
                ThreadsView(appState: appState)
            }
        case .settings:
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                Picker("Project", selection: $appState.selectedProject) {
                    Text("Select project…").tag(nil as Project?)
                    ForEach(appState.projectStore.projects) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                .frame(width: 200)

                Spacer()

                if let thread = appState.currentThread {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(thread.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button(appState.sessionActive ? "End Session" : "Start Session") {
                    appState.toggleSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(appState.sessionActive ? .red : .green)
            }
            .padding(16)

            Divider()

            // Main content area
            if !appState.sessionActive {
                idleView
            } else if appState.isExecuting || !appState.executionOutput.isEmpty {
                ExecutionView(appState: appState)
            } else if !appState.threadMessages.isEmpty {
                SessionThreadView(appState: appState)
            } else {
                listeningView
            }
        }
    }

    private var idleView: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                LogoImage(size: 48)
                Text("Start a session to begin")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Copy anything to your clipboard and Autoclaw will figure out what to do.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                // Recent sessions
                if let project = appState.selectedProject {
                    let recent = appState.sessionStore.threads(for: project.id).prefix(3)
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recent")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                            ForEach(Array(recent)) { thread in
                                Button {
                                    appState.resumeSession(thread: thread)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 9))
                                            .foregroundColor(.accentColor)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(thread.title)
                                                .font(.system(size: 11, weight: .medium))
                                            Text(thread.lastActiveAt.formatted(.relative(presentation: .named)))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(thread.taskCount)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 320)
                    }
                }
            }
            Spacer()
        }
    }

    private var listeningView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("Listening for clipboard…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if !appState.activeApp.isEmpty {
                    HStack(spacing: 6) {
                        Label(appState.activeApp, systemImage: "app.fill")
                        if !appState.activeWindowTitle.isEmpty {
                            Text("—").foregroundStyle(.quaternary)
                            Text(appState.activeWindowTitle).lineLimit(1)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Threads View

struct ThreadsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if appState.selectedProject != nil {
                    Picker("Project", selection: $appState.selectedProject) {
                        Text("All projects").tag(nil as Project?)
                        ForEach(appState.projectStore.projects) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                    .frame(width: 180)
                }
            }
            .padding(16)

            Divider()

            let threads = filteredThreads
            if threads.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No sessions yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(threads) { thread in
                            ThreadRow(
                                thread: thread,
                                projectName: projectName(for: thread.projectId),
                                isActive: appState.currentSessionId == thread.id.uuidString,
                                onTap: {
                                    appState.viewingThread = thread
                                },
                                onResume: {
                                    appState.resumeSession(thread: thread)
                                },
                                onDelete: {
                                    appState.sessionStore.removeThread(id: thread.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var filteredThreads: [SessionThread] {
        if let project = appState.selectedProject {
            return appState.sessionStore.threads(for: project.id)
        }
        return appState.sessionStore.threads.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    private func projectName(for id: UUID) -> String {
        appState.projectStore.projects.first { $0.id == id }?.name ?? "Unknown"
    }
}

struct ThreadRow: View {
    let thread: SessionThread
    let projectName: String
    let isActive: Bool
    var onTap: () -> Void
    var onResume: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // State indicator
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(thread.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(projectName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text("\(thread.taskCount) tasks")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text(thread.lastActiveAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if isHovered {
                    if !isActive {
                        Button {
                            onResume()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Thread Detail View (chat history for a selected session)

struct ThreadDetailView: View {
    @ObservedObject var appState: AppState
    let thread: SessionThread

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 10) {
                Button {
                    appState.viewingThread = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(thread.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text("\(thread.taskCount) tasks")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if appState.currentSessionId != thread.id.uuidString {
                    Button {
                        appState.resumeSession(thread: thread)
                    } label: {
                        Label("Resume", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(16)

            Divider()

            // Messages — show current threadMessages if this is the active session
            if appState.currentSessionId == thread.id.uuidString && !appState.threadMessages.isEmpty {
                SessionThreadView(appState: appState)
            } else {
                // No persisted messages for past sessions yet
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Session messages aren't persisted yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let lastTask = thread.lastTaskTitle {
                        Text("Last task: \(lastTask)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Session Thread View (current session messages in main panel)

struct SessionThreadView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.threadMessages) { msg in
                        sessionMessageRow(msg)
                            .id(msg.id)
                    }

                    if appState.isDeducing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Analyzing…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
            .onChange(of: appState.threadMessages.count) { _ in
                if let last = appState.threadMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionMessageRow(_ msg: ThreadMessage) -> some View {
        switch msg {
        case .clipboard(_, let content, let app, let window, _):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 10)).foregroundStyle(.secondary)
                    if !app.isEmpty { Text(app).font(.system(size: 10)).foregroundStyle(.secondary) }
                    if !window.isEmpty { Text("· \(window)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .screenshot(_, let path, _):
            HStack(spacing: 3) {
                Image(systemName: "camera.fill").font(.system(size: 9))
                Text("Screenshot").font(.system(size: 10, weight: .medium)).lineLimit(1)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int64 {
                    Text("· \(ThreadMessage.formatSize(size))")
                        .font(.system(size: 9)).foregroundStyle(.green.opacity(0.7))
                }
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.green.opacity(0.10))
            .clipShape(Capsule())

        case .userMessage(_, let text, _):
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }

        case .haiku(_, let suggestion, _):
            panelHaikuCard(suggestion)

        case .execution(_, let output, _):
            VStack(alignment: .leading, spacing: 6) {
                Label("Executed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(20)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .error(_, let message, _):
            VStack(alignment: .leading, spacing: 6) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Retry") { appState.sendToHaiku() }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .context(_, let app, let window, _):
            HStack(spacing: 4) {
                if !app.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "app.fill").font(.system(size: 8))
                        Text(app).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(Capsule())
                }
                if !window.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "macwindow").font(.system(size: 8))
                        Text(window).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(Capsule())
                }
                Spacer()
            }

        case .attachment(_, _, let name, let size, _):
            HStack(spacing: 3) {
                Image(systemName: ThreadMessage.iconForFile(name)).font(.system(size: 9))
                Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text("· \(ThreadMessage.formatSize(size))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.purple.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func panelHaikuCard(_ suggestion: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Text(suggestion.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer()
                kindBadge(suggestion.kind)
            }

            if !suggestion.skills.isEmpty {
                HStack(spacing: 4) {
                    ForEach(suggestion.skills, id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Divider().opacity(0.5)

            Text(suggestion.draft)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(suggestion.kind == .execute ? 4 : nil)

            if let plan = suggestion.completionPlan {
                Divider().opacity(0.5)
                Text("Plan").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            HStack {
                switch suggestion.kind {
                case .execute:
                    Button("Skip") { appState.dismissSuggestion() }.buttonStyle(.bordered)
                    Spacer()
                    Button("Run") { appState.approveSuggestion() }.buttonStyle(.borderedProminent)
                case .draft, .answer:
                    Button("Dismiss") { appState.dismissSuggestion() }.buttonStyle(.bordered)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(suggestion.draft, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(suggestion.kind == .draft ? .green : .cyan)
                case .clarification:
                    EmptyView()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.12), lineWidth: 1))
    }

    private func kindBadge(_ kind: TaskKind) -> some View {
        let (label, color): (String, Color) = switch kind {
        case .execute:      ("Execute", .blue)
        case .draft:        ("Draft", .green)
        case .answer:       ("Answer", .cyan)
        case .clarification: ("Question", .purple)
        }
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}
