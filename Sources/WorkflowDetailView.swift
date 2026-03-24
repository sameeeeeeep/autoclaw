import SwiftUI

// MARK: - Workflow Detail View

struct WorkflowDetailView: View {
    @ObservedObject var appState: AppState
    let workflow: SavedWorkflow
    var onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12))
                    Text("Back to Workflows")
                        .font(.system(size: 12))
                }
                .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Header
            HStack(spacing: 14) {
                if !workflow.involvedApps.isEmpty {
                    AppIconRow(apps: workflow.involvedApps, size: 34)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .tracking(-0.3)

                    HStack(spacing: 0) {
                        if workflow.runCount > 0 {
                            Text("Ran \(workflow.runCount) times")
                            Text(" · ").foregroundStyle(theme.textMuted)
                        }
                        Text("Average \(workflow.totalEstimatedFormatted)")
                        if let rel = workflow.lastRunRelative {
                            Text(" · ").foregroundStyle(theme.textMuted)
                            Text("Last run \(rel)")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                // Launch button
                Button {
                    appState.executeWorkflow(workflow)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Launch")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(theme.buttonText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(theme.buttonBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Body: steps + history
            HStack(alignment: .top, spacing: 20) {
                // Steps column
                VStack(alignment: .leading, spacing: 12) {
                    Text("Workflow Steps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    VStack(spacing: 0) {
                        ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                            stepRow(step, index: index)
                            if index < workflow.steps.count - 1 {
                                Divider()
                                    .background(theme.surface)
                            }
                        }
                    }
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, lineWidth: 1)
                    )
                }

                // History column
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Runs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    if workflow.runCount == 0 {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 20))
                                .foregroundStyle(theme.textMuted)
                            Text("No runs yet")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    } else {
                        // Placeholder run history — populated from real data when execution engine lands
                        VStack(spacing: 0) {
                            runHistoryRow(
                                success: workflow.state != .failed,
                                text: workflow.lastResult ?? "\(workflow.steps.count) steps completed",
                                time: workflow.lastRunRelative ?? "recently",
                                duration: workflow.totalEstimatedFormatted
                            )
                        }
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }

                    Spacer()
                }
                .frame(width: 200)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Step Row

    private func stepRow(_ step: WorkflowStep, index: Int) -> some View {
        HStack(spacing: 12) {
            // Number circle
            ZStack {
                Circle()
                    .fill(theme.buttonBg)
                    .frame(width: 24, height: 24)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.buttonText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                if let app = step.app {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text(step.tool)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Run History Row

    private func runHistoryRow(success: Bool, text: String, time: String, duration: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(success ? Theme.green : Theme.red)

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(success ? theme.textPrimary : Theme.red)
                    .lineLimit(1)
                Text("\(time) · \(duration)")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
