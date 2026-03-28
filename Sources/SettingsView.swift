import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var apiKey = ""
    @State private var showingFolderPicker = false
    @State private var keyVisible = false

    var body: some View {
        ScrollView {
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

                // Default Model
                GroupBox("Default Model") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Model", selection: $appState.selectedModel) {
                            ForEach(ClaudeModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Haiku: fast & cheap (deduction, recognition). Sonnet: balanced (extraction, execution). Opus: most capable.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Transcribe
                GroupBox("Transcribe") {
                    VStack(alignment: .leading, spacing: 10) {
                        // Microphone Selection
                        Text("Microphone")
                            .font(.system(size: 12, weight: .medium))

                        HStack(spacing: 8) {
                            Picker("Mic", selection: Binding(
                                get: { AppSettings.shared.selectedMicrophoneUID ?? "__default__" },
                                set: {
                                    AppSettings.shared.selectedMicrophoneUID = ($0 == "__default__") ? nil : $0
                                }
                            )) {
                                Text("System Default").tag("__default__")
                                ForEach(appState.voiceService.availableMicrophones) { mic in
                                    Text(mic.name + (mic.isDefault ? " (default)" : "")).tag(mic.uid)
                                }
                            }
                            .labelsHidden()

                            Button {
                                appState.voiceService.refreshMicrophones()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh microphone list")
                        }

                        Text("Select which microphone to use for voice recording. Refresh if you plug in a new device.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // STT Engine
                        Text("Speech-to-Text Engine")
                            .font(.system(size: 12, weight: .medium))

                        Picker("STT", selection: Binding(
                            get: { AppSettings.shared.sttProvider },
                            set: { AppSettings.shared.sttProvider = $0 }
                        )) {
                            ForEach(STTProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        // WhisperKit model status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.voiceService.whisperKitService.isModelLoaded ? Color.green : Color.orange.opacity(0.7))
                                .frame(width: 7, height: 7)
                            Text("WhisperKit (base.en)")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if appState.voiceService.whisperKitService.isLoadingModel {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            } else if appState.voiceService.whisperKitService.isModelLoaded {
                                Text("Ready")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            } else {
                                Text("Not loaded")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("WhisperKit runs fully local on Neural Engine. Much better accuracy than Apple Speech. Model downloads once (~142MB).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // Cleanup Provider
                        Text("Cleanup Provider")
                            .font(.system(size: 12, weight: .medium))

                        Picker("Cleanup", selection: Binding(
                            get: { AppSettings.shared.cleanupProvider },
                            set: { AppSettings.shared.cleanupProvider = $0 }
                        )) {
                            ForEach(CleanupProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Pre-injection: strips filler words, fixes grammar. Qwen: fast & local via Ollama. Haiku: smarter, needs cloud. None: injects raw voice text.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // Enhance Provider
                        Text("Smart Enhance")
                            .font(.system(size: 12, weight: .medium))

                        Picker("Enhance", selection: Binding(
                            get: { AppSettings.shared.enhanceProvider },
                            set: { AppSettings.shared.enhanceProvider = $0 }
                        )) {
                            ForEach(EnhanceProvider.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Post-injection: context-aware rewrite based on active app (Gmail=professional, Slack=casual, code=syntax). Runs in background, non-blocking.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // ELI5 Dialog Theme
                        Text("ELI5 Dialog")
                            .font(.system(size: 12, weight: .semibold))

                        Picker("Characters", selection: Binding(
                            get: { AppSettings.shared.dialogThemeId },
                            set: { AppSettings.shared.dialogThemeId = $0 }
                        )) {
                            ForEach(DialogTheme.all, id: \.id) { theme in
                                Text("\(theme.char1) & \(theme.char2)").tag(theme.id)
                            }
                        }

                        Text("TV characters that explain what's happening in your Claude Code session. Shows in the transcribe toast.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // Ollama status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.ollamaAvailable ? Color.green : Color.red.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text("Ollama (Qwen 2.5 3B)")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if appState.ollamaAvailable {
                                Text("Running")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            } else {
                                Text("Not running")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                // ARIA Intelligence
                GroupBox("ARIA Intelligence") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Friction Detection", isOn: Binding(
                            get: { !appState.frictionDetector.isSuppressed },
                            set: { appState.frictionDetector.isSuppressed = !$0 }
                        ))
                        .font(.system(size: 12))

                        Text("When enabled, ARIA watches your activity and offers to automate detected friction patterns.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        // Chrome extension status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.browserBridge.isConnected ? Color.green : Color.red.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text("Chrome Extension")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if appState.browserBridge.isConnected {
                                Text("Connected")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                            } else {
                                Text("Not connected")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Load the extension from ChromeExtension/ folder in chrome://extensions (developer mode). Connects on ws://127.0.0.1:9849.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        if appState.browserBridge.isConnected && appState.browserBridge.eventCount > 0 {
                            Text("\(appState.browserBridge.eventCount) DOM events captured this session")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding(8)
                }

                // Keyboard Shortcuts
                GroupBox("Keyboard Shortcuts") {
                    VStack(alignment: .leading, spacing: 6) {
                        shortcutRow(key: "Fn", action: "Start / pause / resume session")
                        shortcutRow(key: "Left ⌥ ×2", action: "End session")
                        shortcutRow(key: "⌥ + Z", action: "Capture screenshot")
                        shortcutRow(key: "⌥ + X", action: "Cycle request mode")
                        shortcutRow(key: "Caps + ⌥ ×2", action: "Toggle voice")
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

                // Data
                GroupBox("Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Saved workflows")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(appState.workflowStore.workflows.count)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Session history")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(appState.sessionStore.threads.count) sessions")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            .appendingPathComponent("Autoclaw").path
                        Button("Open Data Folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: appSupportPath))
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .onAppear {
            apiKey = AppSettings.shared.anthropicAPIKey
        }
    }

    private func shortcutRow(key: String, action: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
                .frame(width: 100, alignment: .trailing)
            Text(action)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
