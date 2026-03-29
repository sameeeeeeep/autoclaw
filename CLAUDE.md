# Autoclaw — CLAUDE.md

## Current Focus (2026-03-30)
- **PM Agent architecture**: Haiku runs as a product/project manager in parallel to the main session. Sandboxed to `.autoclaw/` folder — reads session JSONL + CLAUDE.md/README via `--allowedTools Read,Glob,Write`. Maintains a kanban board (`board.md`), predicts next product actions, updates board on every round.
- **Board PIP**: Floating kanban widget (BoardPIPView/BoardPIPWindow) — separate NSPanel positioned bottom-left. Shows todo/in-progress/done with status indicators. Tapping any item injects at cursor + copies to clipboard. Toggle via icon in toast header.
- **Prediction Add/Use**: Prediction cards now have both "Add" (saves to board.md todo) and "Use" (injects at cursor). Transcript cards have `+` icon to add to board todo.
- **Filler content system**: Pre-written multi-turn dialog fillers (3-4 per theme, all 8 themes) in `.autoclaw/fillers.json`. Auto-plays on 20s timer when idle. Shows "Playing filler" indicator (purple) in Theater PIP. Non-repeatable — fillers are permanently deleted from JSON after playing.
- **Cold opens**: Project-specific cold open dialogs in `.autoclaw/cold-opens.json` (2 per theme). Play immediately when Theater opens (from voice cache if available) while Haiku primes in background. Non-repeatable — deleted from JSON after playing.
- **Voice caching**: Pre-synthesize all fillers + cold opens to WAV files in `.autoclaw/voice-cache/`. Cache key = hash(text + voiceID). Cache warming runs in background batches of 6 when sidecar ready. Cold opens play from cache with zero TTS latency.
- **Theater toggle cleanup**: Disabling theater from toast fully stops everything — filler loop, TTS playback, queue. Same on session end.
- **Theater PIP**: Floating Picture-in-Picture window with animated stage — themed background scenes (8 shows), chibi-style character sprites with idle/talking/gesturing animations, dialogue bubbles, and scrolling transcript. Persists on screen while user works.
- **Theater Mode**: Optional toggle — ELI5 dialog generation + TTS voice playback. When enabled, tempo-adaptive dialog (2-6 lines based on session pace) with in-character term explainers. User messages referenced as a third character from the show.
- **Owned TTS sidecar**: Autoclaw launches and manages the Python TTS server process directly (Pocket TTS on port 7893). Separate pip-installable package: `pip install autoclaw-theater`. Auto-starts when theater PIP opens, auto-kills on app quit. Optional — falls back to text-only if not installed.
- **Dialog queuing + cold opens**: New dialog arriving mid-playback is buffered (appended, not replaced) and played after the current batch finishes. Cold opens bridge the gap.
- **Session tempo tracking**: Tracks JSONL write cadence to classify session pace (rapid/active/relaxed/idle). Dialog turn count adapts: 2 lines during rapid exchanges, 6 lines during relaxed builds.
- **JSONL file watcher**: DispatchSource file watcher on Claude Code session JSONL. 4s debounce. Zero CPU when idle.
- **Liquid glass UI**: macOS 26 Tahoe `.glassEffect()` on toast + theater PIP + board PIP (with fallback for older macOS). Intelligence glow on borders while Haiku generates or TTS speaks.
- **Transcribe pipeline**: Raw WhisperKit output → inject immediately at cursor → enhance in background.
- **Next**: OpenClaw/ClawHub lazy skill discovery, Haiku cloud routing for Analyze mode, polish + ship.

## What this is
Native macOS app (Swift/SwiftUI) — ambient AI at the OS level. Not a copilot, not a chatbot. An agentic intelligence layer.

**Tagline:** autoclaw — ambient AI for macOS | **Org:** The Last Prompt (thelastprompt.ai)

## Four Modes

### 1. Transcribe (voice-to-text) — PRIMARY VALUE PROP
```
Mic → WhisperKit (local) → inject raw at cursor → Smart Enhance (Haiku/Sonnet, non-blocking)
```
Persistent Haiku session per project: first call primes with CLAUDE.md + session context, follow-ups resume. Pre-prompt fires when toast opens — 2 predictions as tappable "Use" cards. Auto-refreshes as session progresses. Raw text injected immediately on stop. Enhanced version offered in background. Pre-prompt and enhance share the same Haiku session thread.

**Status: FULLY BUILT** — WhisperKit STT (base.en, Neural Engine) → raw inject → smart enhance (Haiku/Sonnet/none). Persistent Haiku pre-prompt with JSON format (predictions + multi-turn ELI5 dialog), event-driven JSONL file watcher refresh, feed-back loop. Theater PIP with animated sprite stage + TTS voice playback via owned Python sidecar. 8 dialog themes (TV character pairs) with third-character user framing. Liquid glass UI on macOS 26. Apple SFSpeech as fallback STT.

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

### Haiku (cloud, via autoclawd OAuth) — The PM Agent
- Runs as a product/project manager in parallel to the main Claude Code session
- Agentic: has `--allowedTools Read,Glob,Write` to read session JSONL, CLAUDE.md/README, and `.autoclaw/` folder
- Maintains kanban board (`.autoclaw/board.md`) — moves items to Done, adds new Todos
- Predicts next product-level actions (not code review, not QA)
- Called for Transcribe smart-enhance (post-injection, non-blocking, configurable)
- Called for Transcribe cleanup (if selected as cleanup provider)
- Sandboxed to `.autoclaw/` + session JSONL + project context files — no direct codebase access
- **Status: FULLY WORKING** — PM agent + transcribe cleanup + smart enhance via claude CLI

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
- **Right Shift** (tap) → cycle through modes: Transcribe → Analyze → Task → Learn
- **Double-tap Left Option** → full dismiss (clean slate, end session, clear all state)
- **Option+Z** → dismiss toast without ending session
- **Option+X** → cycle request mode

**Status: FULLY BUILT** — GlobalHotkeyMonitor with CGEvent tap, debounce, double-tap detection all working.

## UI Layer

### Built & Working
- **UnifiedToastView** — Cofia-style card (340px, 16px corners) with mode routing, theater/board toggle icons, Add/Use prediction buttons, + icon on transcripts
- **TheaterPIPView + TheaterPIPWindow** — floating PIP with animated stage: themed backgrounds (TheaterScene), character sprites (TheaterSprite) with idle/talking/gesturing, dialogue bubbles, transcript. 380px wide, liquid glass.
- **BoardPIPView + BoardPIPWindow** — floating kanban widget (280px, bottom-left). Status indicators (empty circle=todo, dot=in-progress, checkmark=done), tap to inject + clipboard. Liquid glass.
- **TheaterSprite** — 16 chibi-style character sprites across 8 themes with per-character appearance (hair, glasses, beard, accessories like lab coat/tie/armor/holographic). Shape-based renderer with animation states.
- **TheaterScene** — 8 themed background scenes: Silicon Valley server room, Rosebud Motel, Dunder Mifflin, Central Perk, Rick's garage lab, 221B Baker Street, Breaking Bad lab, Iron Man workshop. Animated elements (portal spin, fireplace flicker, LED blink, arc reactor pulse).
- **FrictionToastView** — detection → confirm → running → success/error states with step progress
- **TaskApprovalView** — confirm task suggestion before executing
- **ExecutionView** — live output during execution
- **WorkflowDetailView** — view individual saved workflows
- **SettingsView** — model selection, API key entry, STT provider picker, cleanup provider picker, enhance provider picker, ELI5 dialog theme picker, WhisperKit model status, Ollama health check, Chrome extension status, keyboard shortcuts, projects, data

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
- **Theater PIP** with animated stage: 8 themed backgrounds, 16 character sprites (idle/talking/gesturing), dialogue bubbles, scrolling transcript, liquid glass, intelligence glow while TTS speaks
- **Theater Mode** with ELI5 dialog: 2-6 line multi-turn TV character exchange (8 themes) with character personality templates (signature phrases, show-universe analogies, catchphrases), in-character term explainers, third-character user framing, TTS voice playback
- **DialogVoiceService**: Owned Python TTS sidecar (`pip install autoclaw-theater`), auto-launch/kill lifecycle, dialog queuing (buffers new dialog mid-playback), cold opens (play on Theater open from cache), fillers (auto-play on 20s idle timer), voice caching (WAV pre-synthesis), non-repeatable content (deleted from JSON after play), graceful text-only fallback
- **Board PIP**: Floating kanban widget with PM agent maintaining `board.md`. Add predictions/transcripts to todo. Tap items to inject at cursor + clipboard.
- **PM Agent**: Haiku as product manager — sandboxed file access, kanban maintenance, product-level predictions
- **JSONL file watcher**: DispatchSource-based event-driven refresh (replaces 15s polling), 4s debounce
- **Liquid glass UI**: macOS 26 `.glassEffect()` on toast + theater + board with fallback, intelligence border glow while generating
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
- Session tempo tracking (JSONL write cadence → adaptive dialog turns)
- Stale Haiku session detection + auto-reprime
- Imperative prediction enforcement (verb-first commands only)
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
- PM agent with sandboxed file access: Haiku reads session JSONL + CLAUDE.md/README via --allowedTools, maintains .autoclaw/board.md kanban. No direct codebase access — only .autoclaw/ folder (2026-03-30)
- Board PIP as separate floating widget: NSPanel positioned bottom-left (opposite Theater at bottom-right). Tapping any item injects at cursor + copies to clipboard (2026-03-30)
- Non-repeatable fillers/cold opens: after playing, permanently removed from in-memory dict AND deleted from JSON file. Once played, gone forever (2026-03-30)
- Voice caching for instant playback: hash(text + voiceID) → WAV file in .autoclaw/voice-cache/. Cache warming pre-synthesizes all fillers + cold opens in batches of 6. Cold opens play from cache with zero TTS latency (2026-03-30)
- Prediction Add/Use buttons: "Use" injects at cursor (existing), "Add" appends to board.md todo. Transcript cards get + icon for same (2026-03-30)
- Theater toggle fully disables: dismissing theater from toast stops filler loop + TTS + queue, not just PIP window (2026-03-30)
- Theater PIP as separate floating window: animated stage with sprites/backgrounds lives in its own PIP, persists independently from toast. Only dismisses on explicit user action or session end (2026-03-29)
- Owned TTS sidecar as separate pip package: `pip install autoclaw-theater` — Autoclaw searches PATH for CLI first, falls back to server.py in known dirs. Process managed by DialogVoiceService, killed on app quit (2026-03-29)
- Dialog queuing: new dialog arriving mid-playback is buffered, played after current batch. Cold open (random character quip from theme templates) bridges the gap — no silent pause between batches (2026-03-29)
- Character personality templates: each theme includes CHARACTER VOICE GUIDE with signature phrases, catchphrases, show-universe analogies, and cold open quips. Injected into Haiku pre-prompt as tone guardrails — character voice without heavier model (2026-03-29)
- Intent-based predictions: pre-prompt reads user's last 2-3 messages, predicts what they'll TELL Claude to build next — specific features/files/connections from session context, not QA tasks (2026-03-29)
- Theater mode as optional toggle: ELI5 dialog + TTS are opt-in, TTSSidecar is optional — falls back to text-only if not found (2026-03-29)
- JSONL file watcher replaces 15s poll: DispatchSource on session file + 4s debounce — zero CPU when idle, reactive on writes (2026-03-29)
- Liquid glass (.glassEffect) on macOS 26 with solid background fallback for older macOS (2026-03-29)
- Intelligence glow on toast border replaces spinner — `.thinking` state pulses while Haiku generates (2026-03-29)
- Multi-turn dialog (2-6 lines) with in-character term explainers, scaled to session activity (2026-03-29)
- Third-character framing: user messages referenced as show character (Richard, Johnny, Michael, etc.) — dialog stays between 2 main characters only (2026-03-29)
- DialogVoiceService calls SiliconValley TTS sidecar batch endpoint — graceful text-only fallback if sidecar not running (2026-03-29)
- Predictions now factor full conversation history (user + Claude messages), not just project context (2026-03-29)
- Session tempo tracking: JSONL write cadence → adaptive dialog turns (rapid=2, active=4, relaxed=6, idle=3) — dialog finishes before next update, no waste (2026-03-29)
- Stale Haiku session auto-detection: if --resume returns empty, reset and re-prime from scratch (2026-03-29)
- Imperative prediction enforcement: predictions must start with a verb, never questions or observations (2026-03-29)
- Dialog append-only: new dialog lines appended to sessionDialog, never replaced — prevents TTS interruption mid-playback (2026-03-29)
- Theater PIP persistent content: window content set once via SwiftUI @ObservedObject, not recreated on every update (2026-03-29)
- PillView/PillWindow removed: status widget was deprecated, shared code (GlowState, intelligenceGlow, FlowLayout) moved to AutoclawTheme.swift (2026-03-29)
- ELI5 dialog piggybacked on pre-prompt: single Haiku call returns both predictions + character dialog, zero extra latency (2026-03-29)
- 8 dialog themes matching SiliconValley Theater character pairs, configurable in Settings (2026-03-29)
- Haiku returns JSON object `{"predictions":[...], "dialog":[...]}` — more reliable than A:/B: text format, parser has 4-level fallback chain (2026-03-29)
- Persistent Haiku session per project: prime once with --session-id, resume with --resume, no context reloading (2026-03-29)
- Pre-prompt is non-blocking: border glow on toast, user can transcribe immediately (2026-03-29)
- Feed-back loop: after transcription, tell Haiku what user said, get fresh predictions (2026-03-29)
- Transcribe pipeline: skip cleanup, inject raw immediately, enhance in background (2026-03-28)
- Pre-prompt fires BEFORE user speaks — uses project CLAUDE.md + active Claude Code session JSONL (2026-03-28)
- Pre-prompt and enhance share same persistent Haiku session thread (2026-03-28)
- Auto-detect project from ANY window title (regex path extraction), auto-select most recent session (2026-03-28)
- Context fallback chain: CLAUDE.md → README.md → Package.swift → package.json (2026-03-28)
- Chunk drain pattern: pre-stop + post-stop drain of WhisperKit chunks to prevent race condition loss (2026-03-28)
- Qwen is just a bouncer, not a classifier — keep its prompt minimal (2026-03-24)
- Haiku does all smart routing, matched against user's installed MCP tools (2026-03-24)
- Event-driven triggering, not timer-based (don't waste CPU when idle) (2026-03-24)
- Fn is the universal "do" key, Right Shift cycles modes, double-tap Option dismisses (2026-03-26)
- WhisperKit (base.en) is the primary STT — Neural Engine, local, much better accuracy than Apple SFSpeech (2026-03-26)
- autoclaw uses OAuth for Claude/Haiku, not API keys (2026-03-24)

## Build Priority
1. **OpenClaw/ClawHub** — lazy skill discovery for Analyze mode routing
2. **Haiku cloud routing** — smarter Analyze mode detection matching
3. **Polish + ship** — thelastprompt.ai is ready

## Tech Stack
Swift 6.3 + SwiftUI, SPM (Package.swift), WhisperKit (base.en, Core ML), NSStatusItem, toast cards, NSPanel side panel, SQLite/GRDB, launchd, SKILL.md OpenClaw registry, macOS 14+, Ollama (Qwen 2.5 3B)

## File Inventory (54 files)
**Core:** App.swift, AppDelegate.swift, AppState.swift
**Voice:** VoiceService.swift, WhisperKitService.swift, TranscribeService.swift, CursorInjector.swift, DialogVoiceService.swift
**Theater:** TheaterPIPView.swift, TheaterPIPWindow.swift, TheaterSprite.swift, TheaterScene.swift
**Board:** BoardPIPView.swift, BoardPIPWindow.swift
**Analyze:** AnalyzePipeline.swift, ContextBuffer.swift, FrictionDetector.swift, WorkflowMatcher.swift
**Sensors:** ActiveWindowService.swift, ClipboardMonitor.swift, ScreenOCR.swift, BrowserBridge.swift, KeyFrameAnalyzer.swift, ScreenCaptureStream.swift, FileActivityMonitor.swift
**MCP:** CapabilityMap.swift, CapabilityDiscovery.swift
**Task:** TaskDeductionService.swift, TaskSuggestion.swift, ClaudeCodeRunner.swift
**Learn:** WorkflowRecorder.swift, WorkflowExtractor.swift, WorkflowSkillTemplate.swift, LearnMode.swift
**UI:** MainPanelView.swift, MainPanelWindow.swift, UnifiedToastView.swift, FrictionToastView.swift, TaskApprovalView.swift, ExecutionView.swift, WorkflowDetailView.swift, SettingsView.swift, ToastWindow.swift
**Data:** SessionThread.swift, Project.swift, ProjectStore.swift, PreloadedTemplates.swift, Settings.swift
**Util:** GlobalHotkeyMonitor.swift, AutoclawTheme.swift, LogoImage.swift, WebAppResolver.swift, DebugLog.swift, OllamaService.swift

## Spec
/Users/sameeprehlan/Documents/Claude Code/Autoclaw/files/autoclaw_spec_v4.md
