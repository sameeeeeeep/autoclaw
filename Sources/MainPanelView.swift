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
        HSplitView {
            // Sidebar
            VStack(spacing: 4) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 140)
            .padding(10)

            // Content
            Group {
                switch selectedTab {
                case .home:
                    HomeView(appState: appState)
                case .threads:
                    ThreadsView(appState: appState)
                case .settings:
                    SettingsView(appState: appState)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: session controls + project picker
            HStack {
                Picker("Project", selection: $appState.selectedProject) {
                    Text("Select project...").tag(nil as Project?)
                    ForEach(appState.projectStore.projects) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                .frame(width: 200)

                Spacer()

                // Active session indicator
                if let thread = appState.currentThread {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(thread.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                }

                Text("Fn")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)

                Button(appState.sessionActive ? "End Session" : "Start Session") {
                    appState.toggleSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.sessionActive ? .red : .green)
            }
            .padding(16)

            Divider()

            // Main content area
            if !appState.sessionActive {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Press Fn or click Start Session")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Then copy anything to your clipboard — Autoclaw will figure out what to do.\nYou can select a project before or after copying.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    // Quick resume recent threads
                    if let project = appState.selectedProject {
                        let recent = appState.sessionStore.threads(for: project.id).prefix(3)
                        if !recent.isEmpty {
                            VStack(spacing: 4) {
                                Text("Recent sessions")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                ForEach(Array(recent)) { thread in
                                    Button {
                                        appState.resumeSession(thread: thread)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.system(size: 10))
                                                .foregroundColor(.accentColor)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(thread.title)
                                                    .font(.system(size: 11, weight: .medium))
                                                Text(thread.lastActiveAt.formatted(.relative(presentation: .named)))
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text("\(thread.taskCount) tasks")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.06))
                                        .cornerRadius(6)
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
            } else if appState.isExecuting || !appState.executionOutput.isEmpty {
                ExecutionView(appState: appState)
            } else if appState.isDeducing {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analyzing clipboard with Haiku...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if appState.needsProjectSelection {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Clipboard captured! Select a project above.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    if !appState.lastClipboard.isEmpty {
                        Text(String(appState.lastClipboard.prefix(120)) + (appState.lastClipboard.count > 120 ? "..." : ""))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: 400, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(6)
                    }
                }
                Spacer()
            } else if let suggestion = appState.currentSuggestion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text(suggestion.title)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            if !suggestion.skills.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(suggestion.skills, id: \.self) { skill in
                                        Text(skill)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }

                        Divider()

                        Text(suggestion.draft)
                            .font(.system(size: 13))
                            .textSelection(.enabled)

                        if let plan = suggestion.completionPlan {
                            Divider()
                            Text("Completion Plan")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(plan)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Button("Dismiss") {
                                appState.dismissSuggestion()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Approve & Execute") {
                                appState.approveSuggestion()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Listening for clipboard changes...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    if !appState.activeApp.isEmpty {
                        HStack(spacing: 8) {
                            Label(appState.activeApp, systemImage: "app.fill")
                            if !appState.activeWindowTitle.isEmpty {
                                Text("—")
                                Text(appState.activeWindowTitle)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }

                    if appState.selectedProject == nil {
                        Text("No project selected — you'll be prompted to pick one when you copy")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
            }
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
                Text("Session Threads")
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

            // Thread list
            let threads = filteredThreads
            if threads.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Start a session and complete a task to see threads here.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else {
                List {
                    ForEach(threads) { thread in
                        ThreadRow(
                            thread: thread,
                            projectName: projectName(for: thread.projectId),
                            isActive: appState.currentSessionId == thread.id.uuidString,
                            onResume: {
                                appState.resumeSession(thread: thread)
                            },
                            onDelete: {
                                appState.sessionStore.removeThread(id: thread.id)
                            }
                        )
                    }
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
    var onResume: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Label(projectName, systemImage: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text("\(thread.taskCount) tasks")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(thread.lastActiveAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                if let lastTask = thread.lastTaskTitle {
                    Text("Last: \(lastTask)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isActive {
                Button {
                    onResume()
                } label: {
                    Label("Resume", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}
