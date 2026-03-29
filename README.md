<p align="center">
  <img src="assets/logo.png" width="140" alt="Autoclaw logo" />
</p>

<h1 align="center">autoclaw</h1>

<p align="center">
  <strong>Voice-first vibe coding for Claude Code.<br/>It watches your session, predicts your next command, and lets you speak it into existence.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/Swift%206-orange?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
  <img src="https://img.shields.io/badge/status-alpha-yellow" />
</p>

<p align="center">
  <!-- TODO: Replace with GIF — Fn → prediction cards → speak → text injected → Claude executes -->
  <em>[ demo GIF: Fn → see prediction → speak → Claude Code runs it ]</em>
</p>

---

You're vibe coding. Claude just finished wiring up a new component. You already know what comes next — connect it, handle the edge case, move to the next feature. Instead of typing it out:

**Fn.** Two prediction cards appear — autoclaw already read your session and knows what you'll likely say. Tap one. Or speak your own command. Clean, specific text lands at your cursor. Claude picks it up and runs.

You never typed a character. You never broke flow.

That's autoclaw — a **native macOS companion for Claude Code** that turns your voice into the interface. It reads your CLAUDE.md, watches your live session via JSONL, tracks your tempo, and predicts what you'll build next. When you speak, it enhances your words with the exact file names, function names, and context from your session.

Vibe coding, but hands-free.

Built by [The Last Prompt](https://thelastprompt.ai).

---

## Why this exists

Vibe coding with Claude Code is fast — until you have to type. You're in flow, Claude just shipped a feature, and now you need to describe the next thing. You type it out, context-switch from thinking to writing, lose the thread.

Autoclaw removes the typing. It sits at the OS level, watches your Claude Code session in real-time, and gives you two things:

1. **Predictions** — before you even speak, it shows what you'll probably say next
2. **Voice** — when you do speak, it enhances your words with session context and injects them at your cursor

The result: you think it, you say it, Claude builds it. No friction between your brain and the AI.

---

## How it works

```
                    ┌─────────────────────────────┐
                    │  Your Claude Code session    │
                    │  (JSONL file watcher)         │
                    └──────────┬──────────────────┘
                               │ reads live
                               ▼
Fn ──→ Toast appears ──→ 2 prediction cards (tap to use)
       Mic is live           ↑ auto-refresh as session progresses
           │
           ▼
       You speak naturally
           │
           ▼
   WhisperKit (local, Neural Engine)
           │
           ├──→ Raw text injected at cursor INSTANTLY
           │
           └──→ Smart Enhance (background)
                 adds file names, function names,
                 project context from your session
                 ↓
                 enhanced version offered — accept or keep raw
```

### The prediction engine

This is the core magic. When you press Fn, a persistent Haiku session reads:

- Your **CLAUDE.md** — project architecture, file inventory, current focus
- Your **live Claude Code session** — every message, tool call, file edit, error
- Your **session tempo** — how fast you're going (rapid/active/relaxed)

Then it predicts the **two most likely things you'll tell Claude to build next**. Not generic suggestions — specific commands with real file names and feature names from your session:

> *"wire the new sprite animations to the dialog state in TheaterPIPView"*
> *"add error handling for when the TTS sidecar fails to connect on port 7893"*

Predictions refresh automatically via a JSONL file watcher — event-driven, zero CPU when idle, reactive within seconds of Claude finishing a response. No polling.

### Smart enhance

When you speak, the enhancement doesn't just fix grammar. It has your full project context, so when you say *"fix the bug in the toast view"*, it knows you mean `UnifiedToastView.swift`. But it's conservative — it only fills in specifics you clearly referenced. It never puts words in your mouth.

### It works everywhere

While it's optimized for Claude Code, the voice-to-text works in any app — Slack, VS Code, email, Notion, wherever your cursor is. Context-aware tone adjustment (casual for Slack, precise for terminal, polished for docs).

---

## Theater Mode — your session, narrated by TV characters

<p align="center">
  <em>[ screenshot: Theater PIP with Gilfoyle & Dinesh discussing your code session ]</em>
</p>

Optional floating PIP window with an animated stage — themed backgrounds, chibi character sprites with idle/talking/gesturing animations, and dialogue bubbles. TV characters watch your Claude Code session and explain what's happening ELI5-style, completely in character.

> **Gilfoyle:** A DispatchSource — it's basically a file stalker.
> **Dinesh:** So... it watches files? Like my ex watches my Instagram?

8 character duos. Dialog adapts to your coding pace. Optional TTS voice playback. Your messages get referenced as a third character from the show (you're Richard in Silicon Valley, Michael in The Office, etc.).

<details>
<summary><strong>Character pairs</strong></summary>

| Theme | Characters | You are |
|-------|-----------|---------|
| Silicon Valley | Gilfoyle & Dinesh | Richard |
| Schitt's Creek | David & Moira | Johnny |
| The Office | Dwight & Jim | Michael |
| Friends | Chandler & Joey | Ross |
| Rick and Morty | Rick & Morty | Jerry |
| Sherlock | Sherlock & Watson | Lestrade |
| Breaking Bad | Jesse & Walter | Hank |
| Iron Man | Tony & JARVIS | Pepper |

</details>

<details>
<summary><strong>Voice playback setup</strong></summary>

Text-only dialog works out of the box. For character voices:

```bash
pip install autoclaw-theater
# That's it — autoclaw auto-launches the voice server when Theater Mode is active
```

First install downloads ~500MB of model weights (once). [Autoclaw Theater repo →](https://github.com/sameeeeeeep/autoclaw-theater)

</details>

---

## Roadmap

This is **Phase 1** — voice-first vibe coding. The foundation for something bigger.

Autoclaw is designed as a four-mode ambient AI layer that watches, learns, and acts on your behalf at the OS level. Each phase adds a new mode:

| Phase | Mode | Status | What it unlocks |
|-------|------|--------|----------------|
| **1** | **Transcribe** | **Now** | Voice-to-text, predictions, smart enhance, theater — everything above |
| **2** | **Analyze** | Next | Passive autopilot — watches what you do across apps, detects friction, offers to help before you ask. Local Qwen 2.5 3B bouncer → Haiku routing → Claude execution. 8 sensors, 15 workflow templates, MCP tool matching. |
| **3** | **Task** | Planned | Direct execution — speak or paste a command, Claude handles it with full project context + every MCP server you have installed. |
| **4** | **Learn** | Planned | Workflow recording — do something once, Claude extracts a reusable template. Your workflows feed back into Analyze, so it gets smarter over time. |

The end state: an AI that knows your workflows, watches your screen, and handles the routine so you can focus on the interesting parts. Transcribe is the entry point — the other modes are the long game.

---

## Quick start

```bash
git clone https://github.com/sameeeeeeep/autoclaw.git
cd autoclaw
make run
```

### You need

- **macOS 14+**
- **Claude Code CLI** — `npm install -g @anthropic-ai/claude-code`
- **Xcode 15+** (building from source)
- Grant **Accessibility** + **Microphone** when macOS prompts

### Optional

```bash
ollama pull qwen2.5:3b          # local bouncer for Analyze mode
pip install autoclaw-theater     # Theater mode voice playback
# ChromeExtension/ — load unpacked for richer Learn mode context
```

---

## Controls

| Key | Action |
|-----|--------|
| **Fn** | Open toast / start recording / stop recording |
| **Right Shift** | Cycle modes |
| **Left Option ×2** | Full dismiss — end session, clean slate |
| **Option + Z** | Dismiss toast, keep session alive |
| **Option + X** | Cycle sub-mode |

---

## Build

| | |
|---|---|
| `make` / `make spm` | Release build (SPM + WhisperKit) |
| `make debug` | Fast iteration |
| `make legacy` | No WhisperKit, uses Apple Speech fallback |
| `make dmg` | Distributable DMG |
| `make run` | Build + launch |

---

## Under the hood

Full architecture, sensor pipeline, 52-file inventory, and every design decision documented in [CLAUDE.md](CLAUDE.md).

Short version: Swift 6.3 + SwiftUI, WhisperKit (base.en, Neural Engine), persistent Haiku sessions via Claude CLI, JSONL file watcher with 4s debounce, session tempo tracking, liquid glass UI on macOS 26 Tahoe.

---

## Contributing

`make debug` and go. [CLAUDE.md](CLAUDE.md) has the full map. Pick a gap, open a PR.

---

<p align="center">
  <a href="https://thelastprompt.ai">The Last Prompt</a> · <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <em>You think it. You say it. Claude builds it.</em>
</p>
