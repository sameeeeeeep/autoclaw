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

Autoclaw runs as a floating pill widget on your screen. Three modes, each with a specific job:

### Ambient Mode — "I'll watch, you work"

Runs continuously in the background. You don't interact with it — it watches and offers help when it spots friction.

**What it does every 60 seconds:**
1. **Neural Engine** (Apple VNFeaturePrint, on-device, zero cost) detects which screen frames had meaningful visual changes
2. Changed frames are stitched into a **grid image** (max 6 frames per grid, timestamped)
3. Grid sent to **Haiku** with your saved workflow summaries
4. Haiku analyzes the sequence: what apps, what actions, what intent, does this match a learned workflow?

**What it detects:**
- **Cross-app transfers** — you copied from Notion and pasted into Sheets. There's an API for that.
- **File shuttles** — you downloaded a CSV from one tool and uploaded it to another. Direct integration exists.
- **Manual lookups** — you switched to Slack, copied a message, switched back. It can pull that inline.
- **Repetitive navigation** — you keep cycling Chrome → Sheets → Slack → Chrome. That's a workflow.
- **Recognized workflows** — "This looks like your 'Weekly Report' workflow. Want me to run it?"

**When it spots something:**
A toast appears: *"You're copying data from Notion to Google Sheets. I can sync that directly."* Two buttons: **Do it** or **Dismiss**.

### Learn Mode — "Watch me do this once"

You show autoclaw a workflow by doing it normally. It records everything, then extracts structured steps.

**Recording captures (from three sources):**

| Source | What you get | Quality |
|--------|-------------|---------|
| **OCR + Screenshots** | Text near cursor, periodic screen captures, active window crops | Works for all apps. Noisy but gives visual context. |
| **Chrome Extension** | Exact CSS selectors, form field names, typed values, URLs, navigation events | Browser only. Precise enough for replay. |
| **Neural Engine** | Frame change detection — skips captures when nothing changed | Efficiency gate. Saves API cost. |

**Extraction:**
When you stop recording, all three signal sources are merged into a timeline and sent to **Sonnet with vision**. Sonnet sees the screenshots AND the OCR/DOM data and produces human-readable steps like:

```
1. Open Gmail and click Compose               [chrome_click]
2. Enter 'sameep@company.com' in To field      [chrome_form_input]
3. Set subject to 'Weekly Status Update'       [chrome_form_input]
4. Write email body with project updates       [chrome_form_input]
5. Click Send                                  [chrome_click]
```

Not `"Clicked 'Co' in unknown app"`. Actual steps with actual values.

**After saving:**
The workflow goes into your library. Next time ambient mode sees you starting the same pattern, it offers to run it.

### AI Search Mode — "Here's context, figure it out"

Direct interaction. Capture clipboard entries, screenshots, voice — then ask autoclaw to deduce what you need.

**Request modes** (cycle with Option+X):

| Mode | Behavior |
|------|----------|
| **Task** | Executes — edits files, runs commands, uses MCP connectors, ships code |
| **Question** | Answers — queries meetings, searches web, looks up tasks. Never touches code. |
| **Analyze** | Reads deeply — structured assessment, no modifications |
| **Add to Tasks** | Creates ClickUp/project management tasks from captured context |

Each mode invokes a dedicated Claude Code skill that enforces the right guardrails.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  PERCEPTION                                                  │
│                                                              │
│  ScreenCaptureStream ──→ Neural Engine frame embeddings      │
│  ActiveWindowService ──→ app/window/URL (WebAppResolver)     │
│  ClipboardMonitor ────→ content + source app                 │
│  ScreenOCR ───────────→ cursor-proximate text                │
│  FileActivityMonitor ─→ FSEvents (project dirs only)         │
│  BrowserBridge (WS) ──→ Chrome extension DOM events          │
│  VoiceService ────────→ on-device speech transcription        │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  INTELLIGENCE (ARIA)                                         │
│                                                              │
│  KeyFrameAnalyzer                                            │
│    Neural Engine gate → 60s grid stitch → Haiku vision       │
│                                                              │
│  FrictionDetector                                            │
│    Activity buffer → pattern matching → surface offers       │
│    + workflow recognition from Haiku analysis                 │
│                                                              │
│  WorkflowExtractor                                           │
│    OCR + screenshots + DOM events → Sonnet vision → steps    │
│                                                              │
│  CapabilityMap + CapabilityDiscovery                         │
│    MCP tool registry → friction-to-capability matching       │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  EXECUTION                                                   │
│                                                              │
│  Claude Code CLI (stream-json or -p mode)                    │
│  ├── MCP connectors (ClickUp, GitHub, Sheets, etc.)          │
│  ├── Filesystem access (project-scoped)                      │
│  ├── Web search                                              │
│  └── Claude Code Skills (per-mode behavior enforcement)      │
│                                                              │
│  Three-gate approval:                                        │
│    Gate 0: "I noticed X" → Gate 1: "Here's my plan"          │
│    → Gate 2: "Approve execution" → Execute                   │
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
- Ambient friction detection (cross-app transfers, file shuttles, manual lookups)
- Learn mode recording with OCR + screenshots + Chrome extension DOM events
- Workflow extraction via Sonnet vision
- 60-second grid analysis via Haiku vision
- Task deduction from clipboard + voice context
- Claude Code execution with MCP connectors
- Global hotkeys, voice transcription, multi-project support

**What's broken or missing:**
- Workflow browser UI (saved workflows are invisible)
- Thread message persistence (conversations lost on restart)
- Several UI elements are cosmetic only (see PLAN.md)
- Chrome extension reconnection needs work
- Extraction quality varies — needs tuning and testing

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
