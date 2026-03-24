import SwiftUI

// MARK: - Friction Toast State

enum FrictionToastState {
    case detection(FrictionDetector.FrictionSignal)
    case confirmSteps([WorkflowStep])
    case running([WorkflowStep], currentStep: Int)
    case success(result: String, duration: String)
    case error(message: String, failedStep: Int?)
}

// MARK: - Friction Toast View

struct FrictionToastView: View {
    let state: FrictionToastState
    var onAutomate: () -> Void = {}
    var onEditSteps: () -> Void = {}
    var onRun: () -> Void = {}
    var onStop: () -> Void = {}
    var onOpen: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .detection(let signal):
                detectionView(signal)
            case .confirmSteps(let steps):
                confirmView(steps)
            case .running(let steps, let current):
                runningView(steps, current: current)
            case .success(let result, let duration):
                successView(result: result, duration: duration)
            case .error(let message, let failedStep):
                errorView(message: message, failedStep: failedStep)
            }
        }
        .frame(width: 340)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 24, y: 8)
    }

    // MARK: - Detection State

    private func detectionView(_ signal: FrictionDetector.FrictionSignal) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: app icons + dismiss
            HStack {
                AppIconRow(apps: signal.involvedApps, size: 32)
                Spacer()
                dismissButton
            }

            // Question
            Text(signal.suggestion)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Subtitle
            Text("autoclaw can automate this task.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)

            // CTA
            Button(action: onAutomate) {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                    Text("Automate Now")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(theme.buttonBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
    }

    // MARK: - Confirm Steps

    private func confirmView(_ steps: [WorkflowStep]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Confirm workflow steps")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                dismissButton
            }

            // Step list
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

            // Buttons
            HStack(spacing: 10) {
                Button(action: onEditSteps) {
                    Text("Edit Steps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onRun) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Run Now")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(theme.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(theme.buttonBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }

    // MARK: - Running

    private func runningView(_ steps: [WorkflowStep], current: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Running workflow…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Spacer()
                Button(action: onStop) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9))
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Step checklist
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    HStack(spacing: 10) {
                        if idx < current {
                            // Done
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.green)
                                .frame(width: 20)
                        } else if idx == current {
                            // Active
                            ZStack {
                                Circle()
                                    .fill(Theme.blue.opacity(0.15))
                                    .frame(width: 20, height: 20)
                                Image(systemName: "circle.dotted")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.blue)
                            }
                        } else {
                            // Pending
                            ZStack {
                                Circle()
                                    .fill(theme.surface)
                                    .frame(width: 20, height: 20)
                                Text("\(idx + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(theme.textMuted)
                            }
                        }

                        Text(step.description)
                            .font(.system(size: 12, weight: idx == current ? .medium : .regular))
                            .foregroundStyle(idx < current ? theme.textMuted : idx == current ? Theme.blue : theme.textMuted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(current + 1) of \(steps.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.surface)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.blue)
                            .frame(width: geo.size.width * CGFloat(current + 1) / CGFloat(max(steps.count, 1)), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(22)
    }

    // MARK: - Success

    private func successView(result: String, duration: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.green.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflow complete!")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text("Finished in \(duration)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            // Results
            VStack(alignment: .leading, spacing: 6) {
                Text("Results")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .tracking(0.5)
                Text(result)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.green.opacity(colorScheme == .dark ? 0.1 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Open button
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text("Open Sheet")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.buttonBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
    }

    // MARK: - Error

    private func errorView(message: String, failedStep: Int?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.red.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflow failed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    if let step = failedStep {
                        Text("Stopped at step \(step + 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Spacer()
                dismissButton
            }

            // Error message
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.red)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(colorScheme == .dark ? 0.1 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Buttons
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onRetry) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Retry")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
    }

    // MARK: - Shared Components

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundStyle(theme.textMuted)
        }
        .buttonStyle(.plain)
    }
}
