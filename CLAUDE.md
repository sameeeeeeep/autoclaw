# Autoclaw — CLAUDE.md

## What this is
Native macOS app (Swift/SwiftUI) — ambient AI that sits at the OS level and runs your digital life on autopilot. Not a copilot, not a chatbot. An agentic intelligence layer at the interface level.

**Tagline:** autoclaw — ambient AI for macOS
**Org:** The Last Prompt — mission: write the last prompt (prompt-less AI where AI IS the interface)

## Four Modes

### 1. Analyze (ambient detection)
```
Sensors → 60s text buffer → Qwen (filter) → Haiku (route + plan) → Toast → user taps → Claude executes
```
Watches what user does, matches against known workflows/skills/templates, offers to help. User just approves or ignores. This is the passive autopilot — user doesn't initiate anything.

### 2. Learn (workflow recording)
```
Sensors → Claude/Haiku (extract new workflow definition) → Save as template
```
Bypasses Qwen entirely — Qwen isn't smart enough to learn patterns. Records raw session, sends to Claude to extract a NEW reusable workflow definition. This teaches autoclaw something new. Saved workflows then become matchable in Analyze mode.

### 3. Task (direct execution)
```
Clipboard/voice → Claude (with project context) → Result
```
Already built. User copies text or speaks a task, Claude executes it directly. No detection needed — user IS the trigger. Works with any installed MCP tools, OpenClaw skills, pre-loaded templates, or freeform tasks (Claude figures it out).

### 4. Transcribe (voice-to-text)
```
Mic → Whisper/local STT → Qwen (cleanup: remove filler, fix grammar, format) → Types at cursor position
```
Like WhisperFlow. Qwen is perfect for text cleanup — fast, local, no cloud round-trip. A mode people use all day, not just when automating.

## Core Architecture: Two-Brain Model

### Qwen 2.5 3B (local, Ollama) — The Bouncer
- Fast reflex, <6s, runs locally, zero cloud cost
- ONLY job: "is something actionable happening? yes/no" (in Analyze mode) or "clean up this transcription" (in Transcribe mode)
- Does NOT classify, route, or plan — just filters
- Fires on events (app switch, clipboard change, OCR change), NOT on a timer
- Minimum 60s cooldown between calls in Analyze mode
- Debounce 5s after last event before triggering
- Max 20 calls/hour hard cap
- Gets a ~500-800 token text buffer of last 60s of sensor data

### Haiku (cloud, via autoclawd OAuth) — The Concierge
- Only called when Qwen flags something in Analyze mode (maybe 2-5x/hour)
- Also called in Learn mode to extract workflow definitions
- Does ALL the smart work: classification, MCP tool matching, plan building, toast content
- Has access to user's installed MCP tool manifest for routing
- Returns structured detection with fulfilment plan

### Claude (cloud, via autoclawd OAuth) — The Brain
- Called only after user approves (taps toast) in Analyze mode
- Called directly in Task mode (clipboard/voice trigger)
- Called in Learn mode to extract complex workflow patterns
- Executes workflows via Claude Code CLI + MCP servers
- Three execution modes:
  1. **See & Do** — execute a detected task
  2. **Learn & Automate** — extract workflow pattern, save as template, run it
  3. **Understand & Solve** — no template exists, reason about the gap, build custom solution (e.g. creating video2ai)

## Sensor Pipeline (all output TEXT, never images)
- **ActiveWindowService** — app name, window title, URL
- **ClipboardMonitor** — copied text + source app
- **ScreenOCR (Vision)** — UI labels only (~150 chars), NOT full screen text
- **BrowserBridge** — Chrome extension: DOM events, URLs, selectors, typed values
- **KeyFrameAnalyzer** — Neural Engine gates WHEN to OCR, never sends images to LLM
- **Microphone** — voice to text (Transcribe mode + Task mode voice input)

## Fulfilment Routing (Haiku's job)
When something is detected, Haiku routes to the right execution:
1. **Pre-loaded templates** (instant) — ~15 shipped with app, matched by description
2. **Installed MCP tools** (instant) — check user's ~/.claude/mcp.json tool manifest
3. **OpenClaw skills** (lazy, network) — search on demand, install as Claude Code skill
4. **Custom solution** (Claude) — no match anywhere, Claude reasons + builds

## Qwen Detection Model
Single prompt, three detection modes at once:
1. **TASK** — "there's something to DO" (Slack message, email request, calendar reminder, copied task text)
2. **WORKFLOW** — "user is repeating a pattern" (app-switch loops, copy-paste cycles)
3. **NONE** — nothing actionable

Response: `{ type, description, source, matched_template, confidence }`
- confidence < 0.6 → discard
- confidence ≥ 0.6 → pass to Haiku for routing → show toast

## What's already built
- Clipboard-triggered task execution (Task mode core)
- Sensor pipeline (ActiveWindowService, ClipboardMonitor, ScreenOCR, BrowserBridge, KeyFrameAnalyzer)
- OAuth flow via autoclawd
- Status bar pill with mode toggle (ambient/learn/transcribe)
- UnifiedToastView — Cofia-style clean card for all modes (replaces old ThreadToastView)
- FrictionToastView — detection/confirm/running/success/error states for analyze mode
- Learn mode session recording + workflow extraction
- Transcribe mode plumbing (TranscribeService, OllamaService, CursorInjector)
- OllamaService — HTTP client for local Qwen 2.5 3B via Ollama
- Pencil designs: workflow dashboard, toast states, card states, detail view, empty state, dark mode variants, two-brain architecture diagram

## What's NOT built yet
- Ambient detection pipeline — Qwen + Haiku (Analyze mode intelligence)
- ContextBuffer — 60s sliding window aggregating sensor text
- Event-driven Qwen triggering (fire on app switch/clipboard, not timer)
- Pre-loaded workflow templates (~15 common ones)
- Workflow dashboard UI (card grid, designs exist in Pencil)
- Template registry + lazy OpenClaw/ClawHub discovery
- Haiku routing layer (fulfilment matching)
- Whisper/STT integration for transcribe mode (OllamaService + CursorInjector ready)

## Security: Three-Gate Model (mandatory, no exceptions)
- Gate 0: "I noticed X" (toast) — before any work
- Gate 1: "Here's my plan" (confirm steps) — before execution
- Gate 2: "Execute these exact tools" (run) — with intent lock diff

## Key decisions (2026-03-24)
- Qwen is just a bouncer, not a classifier — keep its prompt minimal
- Haiku does all smart routing, matched against user's installed MCP tools
- Event-driven triggering, not timer-based (don't waste CPU when idle)
- Pre-loaded templates ship with the app (don't make user train from scratch)
- OpenClaw skills lazy-load on demand, never bulk load 13K+
- OCR capped at ~150 chars of UI labels per capture (full screen text kills the buffer)
- Screenshots sent to Claude ONLY after user approval (not to Qwen/Haiku)
- autoclaw uses OAuth for Claude/Haiku, not API keys
- Learn mode bypasses Qwen — Qwen can't learn, only match
- Transcribe mode uses Qwen for text cleanup (filler removal, grammar, formatting)
- Four modes: Analyze, Learn, Task, Transcribe — each with distinct pipeline

## Tech stack
Swift 5.9 + SwiftUI, NSStatusItem pill, toast cards, NSPanel side panel, SQLite/GRDB, launchd, SKILL.md OpenClaw registry, macOS 15+, Ollama (Qwen 2.5 3B)

## Design reference
Pencil files with Cofia-inspired UI: workflow dashboard, friction toast, card states, toast states, detail view, empty state, dark mode variants, and two architecture diagrams (4-layer original + two-brain corrected).

## Spec
/Users/sameeprehlan/Documents/Claude Code/Autoclaw/files/autoclaw_spec_v4.md
