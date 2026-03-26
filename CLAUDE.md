# Autoclaw — CLAUDE.md

## What this is
Native macOS app (Swift/SwiftUI) — ambient AI that sits at the OS level and runs your digital life on autopilot. Not a copilot, not a chatbot. An agentic intelligence layer at the interface level.

**Tagline:** autoclaw — ambient AI for macOS
**Org:** The Last Prompt — mission: write the last prompt (prompt-less AI where AI IS the interface)
**Site:** thelastprompt.ai

**Value prop arc:** awareness → action → reach → memory → trust
- It already sees what you see (Vision Pipeline)
- It knows what to do about it (Modes)
- It reaches everywhere you work (Connectors/MCP)
- You do it once, it does it forever (Learn)
- Everything stays yours (Local-first, open source)

## Four Modes

### 1. Transcribe (voice-to-text) — PRIMARY VALUE PROP
```
Mic → WhisperKit (local Neural Engine) → Cleanup (Qwen or Haiku, configurable) → inject at cursor → Smart Enhance (Haiku/Sonnet, configurable, non-blocking)
```
Two-step pipeline:
1. **Cleanup** (pre-injection) — strip filler words ("um", "uh", "like"), fix grammar, basic formatting. Needs to be fast. Configurable: Qwen (local, ~1-2s, free) vs Haiku (cloud, ~2-3s, smarter) vs none (raw). Default: Qwen.
2. **Smart Enhance** (post-injection, non-blocking) — context-aware rewrite based on active app. Gmail gets professional tone, Slack stays casual, code editor gets proper syntax. Configurable: Haiku (default, fast+smart) vs Sonnet (slower, more capable) vs none.

The killer feature. Speak anywhere, cleaned-up text appears at cursor, then a smarter version is offered in the background. Any app becomes a Claude workspace.

**Status: FULLY BUILT** — WhisperKit STT (base.en, Neural Engine) → cleanup (Qwen/Haiku/none, configurable) → CursorInjector → smart enhance (Haiku/Sonnet/none, configurable). Apple SFSpeech available as fallback STT. All settings in SettingsView.

### 2. Analyze (ambient detection)
```
Sensors → 60s text buffer → Qwen (filter) → template/MCP/Claude routing → Toast → user taps → Claude executes
```
Watches what user does, matches against known workflows/skills/templates, offers to help. User just approves or ignores. This is the passive autopilot — user doesn't initiate anything.

**Status: FULLY BUILT** — ContextBuffer (60s window) → Qwen bouncer (event-driven, debounced 5s, 60s cooldown, 20/hr cap) → template matching (15 pre-loaded) → MCP capability matching → Claude custom fallback → FrictionToastView. All sensors wired into ContextBuffer + AnalyzePipeline via AppState.setupARIA().

### 3. Task (direct execution)
```
Clipboard/voice → Claude (with project context) → Result
```
User copies text or speaks a task, Claude executes it directly. No detection needed — user IS the trigger. Works with any installed MCP tools, OpenClaw skills, pre-loaded templates, or freeform tasks.

**Status: FULLY BUILT** — clipboard → TaskDeductionService → ClaudeCodeRunner → result all working.

### 4. Learn (workflow recording)
```
Sensors → Claude/Haiku (extract new workflow definition) → Save as template
```
Bypasses Qwen entirely — Qwen isn't smart enough to learn patterns. Records raw session, sends to Claude to extract a NEW reusable workflow definition. Saved workflows become matchable in Analyze mode.

**Status: FULLY BUILT** — WorkflowRecorder → ScreenCaptureStream → WorkflowExtractor → WorkflowStore all working.

## Build System

### SPM (primary) — `make` or `make spm`
- Package.swift with WhisperKit dependency (+ swift-transformers, swift-crypto, swift-collections)
- `swift build` compiles, Makefile handles .app bundle creation + code signing
- `make debug` for fast iteration, `make spm` for release

### Legacy (fallback) — `make legacy`
- Pure swiftc, no external dependencies, excludes WhisperKitService.swift
- Falls back to Apple SFSpeechRecognizer for STT
- Use if SPM/WhisperKit has issues

## Core Architecture: Two-Brain Model

### Qwen 2.5 3B (local, Ollama) — The Bouncer
- Fast reflex, <6s, runs locally, zero cloud cost
- Jobs: "is something actionable happening?" (Analyze mode), transcript cleanup (Transcribe mode)
- Does NOT classify, route, or plan — just filters and cleans
- Fires on events (app switch, clipboard change, OCR change), NOT on a timer
- Minimum 60s cooldown between calls in Analyze mode
- Debounce 5s after last event before triggering
- Max 20 calls/hour hard cap
- Gets a ~500-800 token text buffer of last 60s of sensor data
- **Status: FULLY WIRED** — OllamaService HTTP client, detection prompt, event-driven calls from sensors, cleanup in TranscribeService

### Haiku (cloud, via autoclawd OAuth) — The Concierge
- Called for Transcribe smart-enhance (post-injection, non-blocking, configurable)
- Called for Transcribe cleanup (if selected as cleanup provider)
- Does ALL the smart work when needed: classification, MCP tool matching, plan building, toast content
- Has access to user's installed MCP tool manifest for routing
- **Status: FULLY WORKING** — transcribe cleanup + smart enhance via claude CLI

### Claude (cloud, via autoclawd OAuth) — The Brain
- Called only after user approves (taps toast) in Analyze mode
- Called directly in Task mode (clipboard/voice trigger)
- Called in Learn mode to extract complex workflow patterns
- Executes workflows via Claude Code CLI + MCP servers
- **Status: Fully working via ClaudeCodeRunner**

## Sensor Pipeline (all output TEXT, never images)
All sensors are **BUILT, POLLING, AND WIRED** into ContextBuffer + AnalyzePipeline:
- **ActiveWindowService** — app name, window title, URL (AXUIElement + AppleScript) → recordAppSwitch()
- **ClipboardMonitor** — copied text + source app (polls changeCount every 0.5s) → recordClipboard()
- **ScreenOCR (Vision)** — UI labels only (~150 chars), cursor-proximity ranked → recordOCR()
- **BrowserBridge** — Chrome extension: DOM events, URLs, selectors (WebSocket ws://127.0.0.1:9849) → recordBrowserEvent()
- **KeyFrameAnalyzer** — Neural Engine 768-dim embeddings gate WHEN to OCR
- **ScreenCaptureStream** — rolling frame buffer + click monitoring via CGEvent taps → recordClick()
- **VoiceService** — WhisperKit (base.en, Neural Engine) with Apple SFSpeech fallback, configurable
- **FileActivityMonitor** — FS event monitoring → recordFileEvent()

All sensor events also trigger `analyzePipeline.onSensorEvent()` when in Analyze mode.

## Fulfilment Routing (LOCAL — templates → MCP → Claude)
When Qwen flags something in Analyze mode:
1. **Pre-loaded templates** (instant) — 15 shipped with app, keyword-matched by description
2. **Installed MCP tools** (instant) — CapabilityMap scans ~/.claude/mcp.json + settings.json + project settings
3. **Custom solution** (Claude) — no match anywhere, Claude reasons + builds

## Hotkey Flow
- **Fn** (tap) → context-sensitive universal key
- **Left Shift** (tap) → cycle through modes: Transcribe → Analyze → Task → Learn
- **Double-tap Left Option** → full dismiss (clean slate, end session, clear all state)
- **Option+Z** → dismiss toast without ending session
- **Option+X** → cycle request mode

**Status: FULLY BUILT** — GlobalHotkeyMonitor with CGEvent tap, debounce, double-tap detection all working.

## UI Layer

### Built & Working
- **UnifiedToastView** — Cofia-style card (340px, 16px corners) with mode routing
- **FrictionToastView** — detection → confirm → running → success/error states with step progress
- **PillView & PillWindow** — status bar pill showing mode + session state
- **TaskApprovalView** — confirm task suggestion before executing
- **ExecutionView** — live output during execution
- **WorkflowDetailView** — view individual saved workflows
- **SettingsView** — model selection, API key entry, STT provider picker, cleanup provider picker, enhance provider picker, WhisperKit model status, Ollama health check, Chrome extension status, keyboard shortcuts, projects, data

### Panel (MainPanelView) — FULLY BUILT
- 4 tabs: Home, Workflows, Threads, Settings
- **Sidebar:** app header, nav tabs, **mode selector** (Transcribe/Analyze/Task/Learn with color indicators), session status
- **Home tab:** project picker, session controls, recent sessions, execution view, listening state
- **Workflows tab:** card grid with state badges, app icons, progress bars, run counts, context menus (rename/run/delete), empty state, detail view navigation
- **Threads tab:** thread list with project filtering, resume/delete, detail view
- **Settings tab:** full config (see above)

### Design Reference
Pencil files with Cofia-inspired UI: workflow dashboard, friction toast, card states, toast states, detail view, empty state, dark mode variants, and two architecture diagrams.

## What's FULLY BUILT
- **Transcribe mode** end-to-end: WhisperKit STT → cleanup (Qwen/Haiku/none) → inject at cursor → smart enhance (Haiku/Sonnet/none)
- **Analyze mode** pipeline: ContextBuffer → Qwen bouncer → template/MCP/Claude routing → FrictionToastView
- **Task mode** end-to-end: clipboard → deduction → execution → result
- **Learn mode** end-to-end: recording → frame buffer → Claude extraction → workflow save
- All 8 sensors implemented, polling, and wired into ContextBuffer + AnalyzePipeline
- SPM build with WhisperKit (base.en) + legacy fallback build
- 15 pre-loaded workflow templates (communication, productivity, dev, data, content, research)
- MCP manifest reading (CapabilityMap scans ~/.claude/mcp.json, settings.json, project settings)
- Hotkey system (Fn, Shift, double-tap Option, Option+Z/X)
- UnifiedToastView + FrictionToastView
- Status bar pill with mode toggle
- Panel: Home, Workflows, Threads, Settings — all tabs complete with mode selector in sidebar
- OAuth flow via autoclawd
- OllamaService HTTP client for Qwen + Ollama health check on startup
- Transcript cleanup step (configurable: Qwen local / Haiku cloud / none)
- Smart enhance (configurable: Haiku / Sonnet / none)
- STT engine (configurable: WhisperKit / Apple Speech)
- CursorInjector (Cmd+V simulation)
- Three-gate security flow in FrictionToastView
- AppState with full session/mode lifecycle + ARIA sensor wiring
- WorkflowMatcher using NLEmbedding similarity
- FrictionDetector with 5 pattern types + recognized workflow matching

## What's NOT BUILT YET

### Remaining Gaps
- **OpenClaw/ClawHub** lazy skill discovery (CapabilityDiscovery exists, not called from Analyze pipeline routing)
- **Haiku cloud routing** in Analyze pipeline (currently routes locally via template/MCP matching + Claude fallback — Haiku routing is a future optimization for smarter matching)

## Security: Three-Gate Model (mandatory, no exceptions)
- Gate 0: "I noticed X" (toast) — before any work
- Gate 1: "Here's my plan" (confirm steps) — before execution
- Gate 2: "Execute these exact tools" (run) — with intent lock diff

## Key Decisions
- Qwen is just a bouncer, not a classifier — keep its prompt minimal (2026-03-24)
- Haiku does all smart routing, matched against user's installed MCP tools (2026-03-24)
- Event-driven triggering, not timer-based (don't waste CPU when idle) (2026-03-24)
- Pre-loaded templates ship with the app (don't make user train from scratch) (2026-03-24)
- OpenClaw skills lazy-load on demand, never bulk load 13K+ (2026-03-24)
- OCR capped at ~150 chars of UI labels per capture (full screen text kills the buffer) (2026-03-24)
- Screenshots sent to Claude ONLY after user approval (not to Qwen/Haiku) (2026-03-24)
- autoclaw uses OAuth for Claude/Haiku, not API keys (2026-03-24)
- Learn mode bypasses Qwen — Qwen can't learn, only match (2026-03-24)
- Transcribe has TWO steps: cleanup (pre-inject) and smart enhance (post-inject) (2026-03-26)
- Cleanup is configurable: Qwen (local/fast), Haiku (cloud/smarter), or none (raw). Default: Qwen (2026-03-26)
- Smart enhance is configurable: Haiku (default), Sonnet (more capable), or none (2026-03-26)
- Fn is the universal "do" key, Shift cycles modes, double-tap Option dismisses (2026-03-26)
- Mode order: Transcribe → Analyze → Task → Learn (removed To Do and Question — not needed) (2026-03-26)
- Transcribe mode is the primary value prop — most achievable, daily-use, gateway feature (2026-03-26)
- WhisperKit (base.en) is the primary STT — Neural Engine, local, much better accuracy than Apple SFSpeech (2026-03-26)
- SPM migration done — Package.swift + WhisperKit dependency, legacy Makefile build as fallback (2026-03-26)
- Analyze pipeline routes locally first (templates → MCP → Claude), Haiku cloud routing is a future optimization (2026-03-26)
- STT engine is configurable: WhisperKit (default) vs Apple Speech (fallback). Settings persist via UserDefaults (2026-03-26)

## Build Priority
1. **OpenClaw/ClawHub** — lazy skill discovery for Analyze mode routing
2. **Haiku cloud routing** — smarter Analyze mode detection matching
3. **Polish + ship** — thelastprompt.ai is ready

## Tech Stack
Swift 6.3 + SwiftUI, SPM (Package.swift), WhisperKit (base.en, Core ML), NSStatusItem pill, toast cards, NSPanel side panel, SQLite/GRDB, launchd, SKILL.md OpenClaw registry, macOS 14+, Ollama (Qwen 2.5 3B)

## File Inventory (49 files)
**Core:** App.swift, AppDelegate.swift, AppState.swift
**Voice:** VoiceService.swift, WhisperKitService.swift, TranscribeService.swift, CursorInjector.swift
**Analyze:** AnalyzePipeline.swift, ContextBuffer.swift, FrictionDetector.swift, WorkflowMatcher.swift
**Sensors:** ActiveWindowService.swift, ClipboardMonitor.swift, ScreenOCR.swift, BrowserBridge.swift, KeyFrameAnalyzer.swift, ScreenCaptureStream.swift, FileActivityMonitor.swift
**MCP:** CapabilityMap.swift, CapabilityDiscovery.swift
**Task:** TaskDeductionService.swift, TaskSuggestion.swift, ClaudeCodeRunner.swift
**Learn:** WorkflowRecorder.swift, WorkflowExtractor.swift, WorkflowSkillTemplate.swift, LearnMode.swift
**UI:** MainPanelView.swift, MainPanelWindow.swift, UnifiedToastView.swift, FrictionToastView.swift, TaskApprovalView.swift, ExecutionView.swift, WorkflowDetailView.swift, SettingsView.swift, PillView.swift, PillWindow.swift, ToastWindow.swift
**Data:** SessionThread.swift, Project.swift, ProjectStore.swift, PreloadedTemplates.swift, Settings.swift
**Util:** GlobalHotkeyMonitor.swift, AutoclawTheme.swift, LogoImage.swift, WebAppResolver.swift, DebugLog.swift, OllamaService.swift

## Spec
/Users/sameeprehlan/Documents/Claude Code/Autoclaw/files/autoclaw_spec_v4.md
