<p align="center">
  <img src="assets/logo.png" width="140" alt="Autoclaw logo" />
</p>

<h1 align="center">Autoclaw</h1>

<p align="center">
  <strong>Ambient AI for macOS — voice-to-text everywhere, workflow automation, and an intelligence layer at the OS level.</strong>
</p>

<p align="center">
  <a href="#transcribe-mode">Transcribe</a> &nbsp;·&nbsp;
  <a href="#analyze-mode">Analyze</a> &nbsp;·&nbsp;
  <a href="#task-mode">Task</a> &nbsp;·&nbsp;
  <a href="#learn-mode">Learn</a> &nbsp;·&nbsp;
  <a href="#setup">Setup</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/language-Swift%206-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
  <img src="https://img.shields.io/badge/status-alpha-yellow" />
</p>

---

## The Problem

Every AI tool today lives *inside* an app. You copy context out, paste it into a chatbot, figure out the right prompt, get a result, then carry it back.

**The human is the integration layer. The human is the bottleneck.**

Autoclaw flips this. It operates at the **OS level** — watching what you do, understanding context, and acting on your behalf. You never switch to it. It's already there.

Built by [The Last Prompt](https://thelastprompt.ai) — mission: write the last prompt.

---

## Four Modes

Cycle modes with **Right Shift**. Start/stop with **Fn**. Dismiss with **double-tap Left Option**.

### Transcribe Mode — "I'll type what you say"

The primary feature. Speak anywhere, raw text appears at your cursor immediately, then a smarter version is offered in background.

```
Mic → WhisperKit (local, Neural Engine) → inject raw at cursor → Smart Enhance (background, non-blocking)
```

**Pre-prompt predictions:** When the toast opens, a persistent Haiku session reads your project context (CLAUDE.md, README) and active Claude Code session history, then predicts the two most likely things you'll say next. Predictions auto-refresh via JSONL file watcher — event-driven, not polled. Tap a suggestion to inject it directly.

**Theater Mode** (optional): A floating Picture-in-Picture window with an animated stage — themed background scenes, chibi-style character sprites with idle/talking/gesturing animations, and dialogue bubbles. TV characters explain what's happening in your session ELI5-style with in-character term explainers. Dialog length adapts to session tempo — 2 lines during rapid exchanges, up to 6 during relaxed builds — so dialog finishes before the next update arrives. Your messages are referenced as a third character from the show (Richard in Silicon Valley, Michael in The Office, etc.). Each theme includes a CHARACTER VOICE GUIDE with signature phrases, catchphrases, and show-universe analogies injected into the pre-prompt. Autoclaw manages the TTS sidecar directly — it launches the Python server (Pocket TTS, port 7893) automatically when theater mode is active and kills it on quit. Falls back to text-only if the sidecar isn't installed (`pip install autoclaw-theater`). Choose from 8 character pairs: Gilfoyle & Dinesh, David & Moira, Dwight & Jim, Chandler & Joey, Rick & Morty, Sherlock & Watson, Jesse & Walter, or Tony & JARVIS.

**Smart Enhance** (post-injection, non-blocking) — context-aware rewrite using the same Haiku session. Proactively adds specific details from project/session context. Configurable: Haiku / Sonnet / none.

**STT Engine:** WhisperKit (base.en, Neural Engine, local) with Apple SFSpeech as fallback. Background chunk transcription every ~25s with hallucination filtering and pre-stop/post-stop drain to prevent chunk loss.

**UI:** Liquid glass effect on macOS 26 Tahoe (solid background fallback on older macOS). Intelligence border glow while Haiku generates predictions or TTS speaks.

### Analyze Mode — "I'll watch, you work"

Passive autopilot. Watches what you do, matches against known workflows, offers to help.

**Two-brain detection:**
1. **Qwen 2.5 3B** (local, Ollama) — the bouncer. Filters sensor data. Event-driven, 60s cooldown, 20/hr cap.
2. **Haiku** (cloud) — the concierge. Routes to: pre-loaded templates → installed MCP tools → custom Claude solution.

### Task Mode — "Do this for me"

Direct execution. Copy text or speak a task, Claude handles it with project context and all your MCP tools.

### Learn Mode — "Watch me do this once"

Records your actions, sends to Claude to extract a reusable workflow. Saved workflows become matchable in Analyze mode.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SENSORS (always on, all output TEXT)                        │
│                                                             │
│  ActiveWindow ─→ app name, window title, URL                │
│  Clipboard ────→ copied text + source app                   │
│  ScreenOCR ────→ UI labels (~150 chars, cursor-ranked)      │
│  BrowserBridge → Chrome extension DOM events (WebSocket)    │
│  KeyFrame ─────→ Neural Engine embeddings gate OCR          │
│  ScreenCapture → rolling frame buffer + click monitoring    │
│  FileActivity ─→ FS event monitoring                        │
│  Voice ────────→ WhisperKit (base.en) / Apple Speech        │
└────────────────────┬────────────────────────────────────────┘
                     │  60s rolling text buffer
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  QWEN 2.5 3B (local, Ollama) — THE BOUNCER                  │
│  Event-driven. 60s cooldown. 20/hr cap. 5s debounce.        │
│  "Is something actionable happening?" → yes/no               │
└────────────────────┬────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  HAIKU (cloud) — THE CONCIERGE                               │
│  Routing: templates → MCP tools → Claude custom              │
└────────────────────┬────────────────────────────────────────┘
                     │  user taps toast → approve
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  CLAUDE (cloud) — THE BRAIN                                  │
│  Executes via Claude Code CLI + MCP servers                  │
│  Three-gate security: detect → plan → execute                │
└─────────────────────────────────────────────────────────────┘
```

### Why Claude Code CLI?

Autoclaw spawns **Claude Code CLI sessions** — every MCP server in `~/.claude/mcp.json` is automatically available. File system, git, code execution, all built in. No API key management per tool.

---

## Setup

### Install from DMG

Download `Autoclaw.dmg` from releases, drag to Applications, right-click → Open on first launch.

### Build from source

```bash
git clone https://github.com/sameeeeeeep/autoclaw.git
cd autoclaw
make run        # build + launch
make dmg        # create distributable DMG
```

### Requirements

| Requirement | Why |
|---|---|
| **macOS 14+** | SwiftUI, Vision, Neural Engine |
| **Xcode 15+** | Swift compiler + frameworks |
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` — used for all AI calls |
| **Accessibility permission** | Hotkeys, cursor injection, active window detection |
| **Microphone permission** | Voice transcription |

### Optional

| | |
|---|---|
| **Ollama + Qwen 2.5 3B** | `ollama pull qwen2.5:3b` — local bouncer for Analyze mode + transcript cleanup |
| **Autoclaw Theater** | Theater mode voice playback — see [Theater Mode setup](#theater-mode-setup) below |
| **Chrome extension** | Load unpacked from `ChromeExtension/` for richer Learn mode |
| **Screen Recording** | Screen capture for key frame analysis + enhance context |

### Theater Mode Setup (Optional)

Theater Mode shows a floating PIP window where TV characters explain your coding session ELI5-style. **Text-only dialog works out of the box** — no extra install needed. To add **character voices**:

```bash
# 1. Install the TTS voice server (Python 3.10+ required)
pip install autoclaw-theater

# 2. That's it — Autoclaw auto-launches the voice server when Theater Mode is active
```

In Autoclaw **Settings → Theater Mode**, toggle it on and pick a character pair (Gilfoyle & Dinesh, David & Moira, etc.).

> **First run note:** The first `pip install` downloads ~500MB of model weights (Pocket TTS + torch). This happens once. If you see text dialogs but no audio, check that `autoclaw-theater` is on your PATH: `which autoclaw-theater`.

[Autoclaw Theater repo →](https://github.com/sameeeeeeep/autoclaw-theater)

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Fn** (tap) | Open toast / start session / stop session |
| **Right Shift** (tap) | Cycle modes: Transcribe → Analyze → Task → Learn |
| **Left Option ×2** | Full dismiss (end session, clean slate, reset to Transcribe) |
| **Option + Z** | Dismiss toast without ending session |
| **Option + X** | Cycle request sub-mode |

---

## Build System

| Command | What it does |
|---------|-------------|
| `make` / `make spm` | Release build (SPM + WhisperKit) |
| `make debug` | Debug build (fast iteration) |
| `make legacy` | Pure swiftc, no WhisperKit (fallback) |
| `make dmg` | Create distributable DMG |
| `make run` | Build + launch |
| `make clean` | Remove build artifacts |

---

## Chrome Extension

The `ChromeExtension/` directory contains a Manifest V3 extension that captures structured DOM events during Learn mode.

| Scenario | OCR alone | With extension |
|----------|-----------|----------------|
| Click a button | `Clicked 'Co' in unknown app` | `Clicked button[aria-label="Compose"] on mail.google.com` |
| Fill a form field | `Clipboard event near 'To'` | `Typed 'sameep@company.com' in input[name="to"]` |
| Navigate | `App switch to Chrome` | `Navigated to notion.so/workspace/sprint-board` |

### Install

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked** → select `ChromeExtension/`
4. Badge shows **ON** when connected, **REC** when recording

---

## Settings

All configurable in the app's Settings tab:

- **STT Engine:** WhisperKit (default) or Apple Speech
- **Smart Enhance:** Haiku (default) / Sonnet / None
- **Theater Mode:** Toggle ELI5 dialog generation + TTS voice playback
- **Dialog Theme:** 8 TV character pairs for session commentary
- **Projects:** Multiple project directories with context, auto-detected from active window
- **Ollama:** Health check, model status

---

## Tech Stack

Swift 6.3 + SwiftUI, SPM (Package.swift), WhisperKit (base.en, Core ML/Neural Engine), Ollama (Qwen 2.5 3B), NSStatusItem pill, toast cards, NSPanel, SQLite/GRDB, macOS 14+

---

## Contributing

The codebase is Swift with SPM. `make debug` for fast iteration. Pick anything from the remaining gaps in CLAUDE.md, open a PR.

---

## License

[MIT](LICENSE) — The Last Prompt, 2025.

---

<p align="center">
  <em>AI shouldn't live in an app. It should be the interface.</em>
</p>
