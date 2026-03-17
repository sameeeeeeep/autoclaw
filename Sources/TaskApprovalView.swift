import SwiftUI

// MARK: - Task Suggestion Toast

struct TaskToastView: View {
    @ObservedObject var appState: AppState
    let suggestion: TaskSuggestion
    var onApprove: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: skill chips + dismiss
            HStack(alignment: .center, spacing: 4) {
                // Skill chain chips
                if !suggestion.skills.isEmpty {
                    ForEach(Array(suggestion.skills.enumerated()), id: \.offset) { index, skill in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.quaternary)
                        }
                        Text(skill)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.18))
                            .clipShape(Capsule())
                            .foregroundStyle(Color.blue)
                    }
                }

                Spacer()

                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }

            // Headline
            Text(suggestion.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            // Draft preview
            Text(suggestion.draft)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)

            // Completion plan
            if let plan = suggestion.completionPlan {
                Text(plan)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            // Context chips
            if !appState.clipboardCapturedApp.isEmpty || !appState.clipboardCapturedWindow.isEmpty {
                HStack(spacing: 6) {
                    if !appState.clipboardCapturedApp.isEmpty {
                        Label(appState.clipboardCapturedApp, systemImage: "app.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    if !appState.clipboardCapturedWindow.isEmpty {
                        Text(appState.clipboardCapturedWindow)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            // Action row
            HStack(spacing: 8) {
                Button("Run now", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Skip") { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
    }
}

// MARK: - Clarification Toast

struct ClarificationToastView: View {
    @ObservedObject var appState: AppState
    let clarification: Clarification
    var onRespond: (String) -> Void
    var onDismiss: () -> Void

    @State private var freeformAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row
            HStack(alignment: .center) {
                Label("Needs info", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.purple)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Question
            Text(clarification.question)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)

            // Context explanation
            if let context = clarification.context {
                Text(context)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            // Option buttons (if available)
            if let options = clarification.options, !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            onRespond(option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.system(size: 11))
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Freeform answer field
            HStack(spacing: 6) {
                TextField("Type an answer…", text: $freeformAnswer)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        if !freeformAnswer.isEmpty {
                            onRespond(freeformAnswer)
                        }
                    }

                Button {
                    if !freeformAnswer.isEmpty {
                        onRespond(freeformAnswer)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(freeformAnswer.isEmpty ? Color.gray : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(freeformAnswer.isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
    }
}

// MARK: - Error Toast

struct ErrorToastView: View {
    let message: String
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row
            HStack(alignment: .center) {
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.red.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.red)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Error message
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Actions
            HStack(spacing: 8) {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
    }
}

// MARK: - Project Picker Toast

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
