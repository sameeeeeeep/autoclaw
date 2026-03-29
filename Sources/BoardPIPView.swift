import SwiftUI

/// Floating kanban board widget.
/// Reads .autoclaw/board.md, displays todo/in-progress/done with clean visual hierarchy.
/// Todo items are tappable — injects the task text at cursor via TranscribeService.
struct BoardPIPView: View {
    let projectPath: String
    let onUse: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @State private var board = BoardItems()
    @State private var refreshTick = 0

    private var boardPath: String { "\(projectPath)/.autoclaw/board.md" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.teal)
                    Text("Board")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.teal.opacity(0.12))
                .clipShape(Capsule())

                Spacer()

                // Counts
                HStack(spacing: 8) {
                    if !board.inProgress.isEmpty {
                        countBadge(board.inProgress.count, color: Theme.blue, icon: "circle.dotted")
                    }
                    countBadge(board.todo.count, color: theme.textMuted, icon: "circle")
                    countBadge(board.done.count, color: Theme.green, icon: "checkmark.circle.fill")
                }

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
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .background(theme.border)
                .padding(.horizontal, 14)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    // In Progress
                    ForEach(Array(board.inProgress.enumerated()), id: \.offset) { _, item in
                        boardRow(item, status: .inProgress)
                    }

                    // Todo
                    ForEach(Array(board.todo.enumerated()), id: \.offset) { _, item in
                        boardRow(item, status: .todo)
                    }

                    // Done — collapsed, show last 3
                    if !board.done.isEmpty {
                        Divider()
                            .background(theme.border)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)

                        ForEach(Array(board.done.prefix(3).enumerated()), id: \.offset) { _, item in
                            boardRow(item, status: .done)
                        }
                        if board.done.count > 3 {
                            Text("+\(board.done.count - 3) completed")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .modifier(BoardLiquidGlass(fallbackColor: theme.card))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 20, y: 6)
        .onAppear { reload() }
    }

    // MARK: - Row

    private enum ItemStatus {
        case todo, inProgress, done
    }

    private func boardRow(_ text: String, status: ItemStatus) -> some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            onUse(text)
        }) {
            HStack(spacing: 10) {
                // Status indicator
                switch status {
                case .todo:
                    Circle()
                        .strokeBorder(theme.textMuted.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                case .inProgress:
                    ZStack {
                        Circle()
                            .strokeBorder(Theme.blue.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(Theme.blue)
                            .frame(width: 5, height: 5)
                    }
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.green.opacity(0.5))
                }

                Text(text)
                    .font(.system(size: 11, weight: status == .inProgress ? .medium : .regular))
                    .foregroundStyle(status == .done ? theme.textMuted : theme.textPrimary)
                    .strikethrough(status == .done, color: theme.textMuted.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(status == .done ? 0.6 : 1)
    }

    // MARK: - Helpers

    private func countBadge(_ count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color.opacity(0.7))
    }

    private func reload() {
        guard let content = try? String(contentsOfFile: boardPath, encoding: .utf8) else { return }
        board = BoardItems.parse(content)
    }
}

// MARK: - Liquid Glass

private struct BoardLiquidGlass: ViewModifier {
    let fallbackColor: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        } else {
            content
                .background(fallbackColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
