<p align="center">
  <img src="assets/logo.png" width="140" alt="Autoclaw logo" />
</p>

<h1 align="center">Autoclaw</h1>

<p align="center">
  <strong>Ambient AI for macOS — watches your screen, learns your workflows, automates your work.</strong>
</p>

<p align="center">
  <a href="#how-it-works">How it works</a> &nbsp;·&nbsp;
  <a href="#learn-mode">Learn mode</a> &nbsp;·&nbsp;
  <a href="#setup">Setup</a> &nbsp;·&nbsp;
  <a href="#chrome-extension">Chrome extension</a> &nbsp;·&nbsp;
  <a href="PLAN.md">Roadmap</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" />
  <img src="https://img.shields.io/badge/language-Swift-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
  <img src="https://img.shields.io/badge/status-early%20alpha-yellow" />
</p>

---

<!--
  SCREENSHOTS: Add screenshots of the running app here.
  Capture the pill widget, the toast thread, learn mode recording,
  and a friction detection offer. Save to assets/ folder.

  Example:
  <p align="center">
    <img src="assets/screenshot_pill.png" width="250" alt="Pill widget" />
    <img src="assets/screenshot_toast.png" width="350" alt="Toast thread" />
    <img src="assets/screenshot_learn.png" width="350" alt="Learn mode" />
  </p>
-->

## The Problem

Every AI tool today lives *inside* an app. You copy context out of one app, paste it into a chatbot, figure out the right prompt, get a result, then manually carry it back.

**The human is the integration layer. The human is the bottleneck.**

Autoclaw flips this. It operates at the **OS level** — watching everything you do across every app, understanding your intent, and acting on your behalf. You never switch to it. It's already there.

This is the first implementation of **ARIA** (Agentic Reality Interface Architecture) — AI as the interface to your computer, not as a chatbot within it.

Built by [The Last Prompt](https://thelastprompt.ai).

---

## How It Works

Autoclaw runs as a floating pill widget on your screen. Four modes, each with a distinct pipeline. Cycle with **Left Shift**, start/stop with **Fn**, dismiss with **double-tap Left Option**.

### 1. Transcribe — "I'll type what you say"

Voice-to-text that types wherever your cursor is. Like WhisperFlow.

- SFSpeechRecognizer captures your voice (with audio engine pre-warming for instant startup)
- Raw text injected immediately at cursor via Cmd+V simulation
- Haiku then suggests a context-aware enhanced version (polished email on Gmail, better prompt on Freepik, etc.)
- Also works with clipboard: copy text in transcribe mode and Haiku will polish it for the active app

### 2. Analyze — "I'll watch, you work"

The passive autopilot. Runs in the background, watches what you do, offers help.

**Two-brain detection:**
1. **Qwen 2.5 3B** (local, Ollama, <2s) — the bouncer. Filters sensor data every 60s. Single prompt, three detection modes: TASK (something to do), WORKFLOW (repetitive pattern), NONE.
2. **Haiku** (cloud, fast) — the concierge. Only called when Qwen flags something. Routes to the right fulfilment: pre-loaded template, installed MCP tool, ClawHub skill, or custom Claude solution.

**What gets detected:**
- **Tasks on screen** — Slack message asking you to do something, email request, calendar reminder
- **Repetitive workflows** — Sheets → Gmail → Sheets → Gmail loop, copy-paste cycles
- **Automatable patterns** — downloading a CSV from one tool, uploading to another

**When it spots something:**
A clean, Cofia-style toast card appears with app icons, a clear description, and a single **Automate Now** button. One tap → Claude executes.

### 3. Task — "Here's what I need, do it"

Direct execution. Copy text or speak a task, Claude handles it with your project context. No detection needed — you are the trigger. Works with any installed MCP tools, OpenClaw skills, pre-loaded templates, or freeform tasks.

**Request sub-modes** (cycle with Option+X): Task, To Do, Question.

### 4. Learn — "Watch me do this once"

Bypasses Qwen entirely (it's not smart enough to learn). Records your raw session, sends to Claude/Haiku to extract a new reusable workflow definition.

**Recording captures:** ActiveWindow, ClipboardMonitor, ScreenOCR, BrowserBridge (Chrome extension DOM events), KeyFrameAnalyzer gating.

**Extraction:** When you stop recording, sensor data is sent to Claude to produce structured steps. Saved workflows become matchable in Analyze mode.

### Three execution modes (Claude's job after user approval)

1. **See & Do** — execute a detected task
2. **Learn & Automate** — extract workflow pattern, save as template, run it
3. **Understand & Solve** — no template exists, reason about the gap, build custom solution (e.g. creating video2ai)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  SENSORS (always on, all output TEXT)                         │
│                                                              │
│  ActiveWindowService ──→ app name, window title, URL         │
│  ClipboardMonitor ────→ copied text + source app             │
│  ScreenOCR (Vision) ──→ UI labels only (~150 chars)          │
│  BrowserBridge (WS) ──→ Chrome ext DOM events, selectors     │
│  KeyFrameAnalyzer ────→ Neural Engine gates WHEN to OCR      │
│  VoiceService ────────→ on-device speech transcription        │
└──────────────────┬───────────────────────────────────────────┘
                   │  60s rolling text buffer (500-800 tokens)
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  QWEN 2.5 3B (local, Ollama, <2s) — THE BOUNCER             │
│                                                              │
│  Single prompt, 3 detection modes:                           │
│    TASK — "there's something to DO"                          │
│    WORKFLOW — "user is repeating a pattern"                   │
│    NONE — nothing actionable                                 │
│                                                              │
│  Matches against template registry. Event-driven, not timer. │
│  Min 60s cooldown. Max 20 calls/hour. Debounce 5s.           │
└──────────────────┬───────────────────────────────────────────┘
                   │  confidence ≥ 0.6
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  HAIKU (cloud, ~1s) — THE CONCIERGE                          │
│                                                              │
│  Fulfilment routing cascade:                                 │
│    1. Pre-loaded templates (instant, ~15 shipped)            │
│    2. Installed MCP tools (~/.claude/mcp.json manifest)      │
│    3. ClawHub skills (lazy search, install on demand)        │
│    4. Custom solution (Claude reasons + builds)              │
│                                                              │
│  Returns: toast content, execution plan, app icons           │
└──────────────────┬───────────────────────────────────────────┘
                   │  toast → user taps "Automate Now"
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  CLAUDE (cloud) — THE BRAIN                                  │
│                                                              │
│  Claude Code CLI executes via MCP servers                    │
│  ├── Every MCP server in ~/.claude/mcp.json available        │
│  ├── Pre-loaded templates pre-fill execution plans           │
│  ├── ClawHub skills install as Claude Code skills            │
│  └── Screenshots sent with task (after user approval only)   │
│                                                              │
│  Three-gate security:                                        │
│    Gate 0: "I noticed X" → Gate 1: "Here's my plan"          │
│    → Gate 2: "Execute these exact tools" → Run               │
└──────────────────────────────────────────────────────────────┘
```

### Why Claude Code, not the API directly?

Autoclaw doesn't call the Anthropic API. It spawns **Claude Code CLI sessions** (`claude -p` for single-shot, `--output-format stream-json` for interactive). This means:

- Every MCP server you have configured in `~/.claude/mcp.json` is automatically available
- File system access, code execution, git operations — all built in
- Skills system for per-mode behavior rules
- Session continuity for multi-turn workflows
- You don't manage API keys for individual tools — Claude Code handles authentication

### Why Neural Engine for frame gating?

Sending every screen frame to an API would be expensive and slow. Apple's `VNGenerateImageFeaturePrintRequest` runs entirely on the Neural Engine — zero CPU, zero memory, zero API cost. It produces a 768-dim embedding per frame. Cosine distance between consecutive embeddings tells you if the screen actually changed. Only frames that pass the gate get sent to Haiku.

This is the same approach used in [video2ai](https://github.com/sameeeeeeep/video2ai) for key frame extraction from video files, adapted for live screen capture.

---

## Chrome Extension

The `ChromeExtension/` directory contains a Manifest V3 extension that captures structured DOM events during Learn mode.

### What it captures vs OCR

| Scenario | OCR alone | With extension |
|----------|-----------|----------------|
| Click a button | `Clicked 'Co' in unknown app` | `Clicked button[aria-label="Compose"] on mail.google.com` |
| Fill a form field | `Clipboard event near 'To'` | `Typed 'sameep@company.com' in input[name="to"]` |
| Select a dropdown | `Clicked 'High' in Chrome` | `Selected 'High Priority' in select[name="priority"]` |
| Navigate | `App switch to Chrome` | `Navigated to notion.so/workspace/sprint-board` |
| Submit a form | `Clicked 'Sub' near button` | `Submitted form on mail.google.com/mail` |

### How it connects

```
Chrome Extension ──── WebSocket (ws://127.0.0.1:9849) ────→ BrowserBridge.swift
                                                              │
                                                    ┌─────────┘
                                                    ▼
                                         AppState.browserEventBuffer
                                                    │
                                         WorkflowExtractor (merged with OCR timeline)
```

The extension is passive until autoclaw tells it to record. Autoclaw sends `start_recording` / `stop_recording` commands over the WebSocket. A keepalive ping every 20s prevents the MV3 service worker from sleeping.

### Install

1. Open `chrome://extensions`
2. Enable **Developer mode** (top right)
3. Click **Load unpacked**
4. Select the `ChromeExtension/` folder
5. Badge shows **ON** when connected to autoclaw, **REC** when recording

---

## Connectors

Autoclaw inherits every MCP server configured in your Claude Code setup (`~/.claude/mcp.json`). These are used both for **direct execution** (when you ask autoclaw to do something) and for **capability matching** (when ARIA detects friction and checks if a tool exists to solve it).

| Connector | What autoclaw uses it for |
|-----------|--------------------------|
| **ClickUp** | Create/search/update tasks, time tracking, sprint management |
| **Granola** | Query meeting notes, transcripts, action items |
| **Google Sheets** | Read/write spreadsheet data |
| **GitHub** | Issues, PRs, code search, branch management |
| **Web Search** | Real-time information lookup |
| **Filesystem** | Project file access (Task mode only, scoped to project dir) |

Add any MCP server and autoclaw can use it immediately — no configuration in autoclaw needed.

---

## Setup

```bash
git clone https://github.com/thelastprompt/autoclaw.git
cd autoclaw
make run
```

### Requirements

| Requirement | Why |
|---|---|
| **macOS 13+** | SwiftUI, Vision framework, Neural Engine APIs |
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` — autoclaw spawns this for all AI calls |
| **Anthropic API key** | Set in autoclaw settings or `ANTHROPIC_API_KEY` env var |
| **Accessibility permission** | Global hotkeys, active window detection |
| **Screen Recording permission** | Screen capture for key frame analysis |

### Optional

| | |
|---|---|
| **Chrome extension** | Load unpacked from `ChromeExtension/` for richer Learn mode |
| **MCP servers** | Configure in `~/.claude/mcp.json` for connectors |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Fn** | Start session / pause / resume / cycle through states |
| **Left Option ×2** | End session |
| **Option + Z** | Capture screenshot into current session |
| **Option + X** | Cycle request mode (Task → Question → Analyze → Add to Tasks → Learn) |
| **Caps Lock + Option ×2** | Toggle voice transcription |

---

## Project Structure

```
Sources/
│
│  Perception
├── ScreenCaptureStream.swift   — screen capture, active window cropping, click detection
├── ActiveWindowService.swift   — app/window/URL tracking + WebAppResolver
├── ClipboardMonitor.swift      — clipboard content polling
├── ScreenOCR.swift             — Vision OCR with cursor proximity ranking
├── FileActivityMonitor.swift   — FSEvents file watcher
├── WorkflowRecorder.swift      — event recording (explicit + passive modes)
│
│  ARIA Intelligence
├── KeyFrameAnalyzer.swift      — Neural Engine embeddings, 60s grid analysis, Haiku vision
├── FrictionDetector.swift      — activity pattern matching, workflow recognition
├── WorkflowExtractor.swift     — Sonnet vision extraction from recordings
├── WorkflowMatcher.swift       — NLEmbedding similarity for workflow matching
├── CapabilityMap.swift         — MCP tool registry
├── CapabilityDiscovery.swift   — web search for new integrations
├── WebAppResolver.swift        — browser URLs → semantic app identities
│
│  Browser Integration
├── BrowserBridge.swift         — WebSocket server for Chrome extension
│
│  Execution
├── ClaudeCodeRunner.swift      — Claude Code CLI (stream-json + single-shot)
├── TaskDeductionService.swift  — ambient task analysis and intent extraction
│
│  Interface
├── PillView.swift              — floating pill widget (5 collapse levels)
├── TaskApprovalView.swift      — toast UI with full session thread
├── MainPanelView.swift         — dashboard (home, threads, settings)
├── ToastWindow.swift           — floating glass panel with drag & drop
├── AppState.swift              — central state, mode routing, ARIA wiring
├── AppDelegate.swift           — window management, hotkey setup
└── ...

ChromeExtension/
├── manifest.json               — Manifest V3
├── content.js                  — DOM event capture
├── background.js               — WebSocket client + recording state
├── popup.html/js               — connection status UI
└── icon*.png
```

---

## Current Status

This is early alpha. The intelligence pipeline works — perception, analysis, friction detection, workflow extraction. But there are significant gaps in the user-facing product. See [PLAN.md](PLAN.md) for the full roadmap.

**What works today:**
- Ambient friction detection (cross-app transfers, file shuttles, manual lookups, workflow recognition)
- Learn mode recording with OCR + screenshots + Chrome extension DOM events
- Workflow extraction via Sonnet vision with rich step details (app, action, target, value, selector)
- Screenshots passed to extraction model via CLI Read tool for real vision analysis
- Cofia-style friction toast UI with app icons and single-action "Automate Now" button
- 60-second grid analysis via Haiku vision
- Resolved web app names in recordings (Gmail not "Google Chrome")
- Task deduction from clipboard + voice context
- Claude Code execution with MCP connectors
- Global hotkeys, voice transcription, multi-project support

**What's broken or missing:**
- Workflow execution engine (step-by-step progress, parameterization)
- Thread message persistence (conversations lost on restart)
- Several UI elements are cosmetic only (see PLAN.md)
- Chrome extension reconnection needs work

---

## Contributing

See [PLAN.md](PLAN.md) for prioritized work items. P0 items block the core product; P3 items are future vision. Pick anything, open a PR.

The codebase is pure Swift (no Xcode project — builds with `make` via `swiftc`) plus a small Chrome extension in vanilla JS.

---

## License

[MIT](LICENSE) — The Last Prompt, 2025.

---

<p align="center">
  <em>AI shouldn't live in an app. It should be the interface.</em>
</p>
