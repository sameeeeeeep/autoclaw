import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var apiKey = ""
    @State private var showingFolderPicker = false
    @State private var keyVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))

            // API Key
            GroupBox("Anthropic API Key") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if keyVisible {
                            TextField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            keyVisible.toggle()
                        } label: {
                            Image(systemName: keyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)

                        Button("Save") {
                            AppSettings.shared.setAnthropicAPIKey(apiKey)
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKey.isEmpty)

                        if !AppSettings.shared.anthropicAPIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                        }
                    }

                    if !AppSettings.shared.anthropicAPIKey.isEmpty {
                        Text("Key saved (\(String(AppSettings.shared.anthropicAPIKey.prefix(12)))...)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    Text("Used for task deduction (Haiku) and execution (Claude Code). Also reads ANTHROPIC_API_KEY from env.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            // Hotkey info
            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Fn")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                        Text("Toggle session start / end")
                            .font(.system(size: 12))
                    }
                    Text("Works globally — press from any app to start or stop a session.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Requires Accessibility permission in System Settings > Privacy & Security > Accessibility.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            // Projects
            GroupBox("Projects") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.projectStore.projects) { project in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(project.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(project.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appState.projectStore.remove(project)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Add Project Folder...") {
                        showingFolderPicker = true
                    }
                    .fileImporter(
                        isPresented: $showingFolderPicker,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            let project = appState.projectStore.addFromPath(url.path)
                            if appState.selectedProject == nil {
                                appState.selectedProject = project
                            }
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            apiKey = AppSettings.shared.anthropicAPIKey
        }
    }
}
