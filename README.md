<p align="center">
  <img src="assets/logo.png" width="140" alt="Autoclaw logo" />
</p>

<h1 align="center">autoclaw</h1>

<p align="center">
  <strong>Ambient AI for macOS. Watches your session. Predicts your next move. Speaks it into existence.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/Swift%206-orange?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
  <img src="https://img.shields.io/badge/status-alpha-yellow" />
</p>

<p align="center">
  <!-- TODO: Replace with GIF -->
  <em>[ demo GIF: Fn → prediction cards → speak → text lands → Claude builds it ]</em>
</p>

---

You're deep in a Claude Code session. Claude just finished wiring up a component. You know what comes next. Instead of typing:

**Fn.** Two cards appear — autoclaw already read your session and knows what you'll say. Tap one. Or speak. Clean text lands at your cursor. Claude picks it up and runs.

No typing. No context switch. No friction.

Built by [The Last Prompt](https://thelastprompt.ai).

---

## The loop

```
You think it → You say it → Claude builds it
```

That's the whole product. Everything below exists to make that loop instant.

---

## How it works

```
Your Claude Code session (JSONL)
       │ watches live
       ▼
  Fn → Toast appears
       ├── 2 prediction cards (tap "Use" or "Add" to board)
       ├── Mic goes live
       │     │
       │     ▼ You speak naturally
       │     │
       │     ├── WhisperKit (local, Neural Engine)
       │     │     ├── Raw text → cursor INSTANTLY
       │     │     └── Smart Enhance (background) → file names,
       │     │         function names, session context → accept or keep raw
       │     │
       │     └── + button saves transcript to kanban board
       │
       └── Theater PIP (optional)
             TV characters narrate your session ELI5-style
             with voice playback, animations, and zero shame
```

### Predictions

A persistent Haiku session reads your **CLAUDE.md**, your **live session JSONL**, and your **coding tempo** — then predicts the two most likely things you'll tell Claude to build next. Not generic suggestions. Specific commands with real file names from your session:

> *"wire the sprite animations to dialog state in TheaterPIPView"*
> *"add error handling for TTS sidecar connection on port 7893"*

Predictions refresh automatically via JSONL file watcher — event-driven, zero CPU when idle. A PM agent (Haiku) runs in parallel, maintaining a kanban board of your project and feeding predictions from product context, not just code diffs.

### Smart enhance

When you speak, enhancement doesn't just fix grammar. It has your full project context — when you say *"fix the bug in the toast"*, it knows you mean `UnifiedToastView.swift`. Conservative by design — fills in specifics you clearly referenced, never puts words in your mouth.

### Works everywhere

Voice-to-text works in any app — Slack, VS Code, email, Notion. Context-aware tone adjustment: casual for Slack, precise for terminal, polished for docs.

---

## Theater Mode

<p align="center">
  <em>[ screenshot: Theater PIP — Gilfoyle & Dinesh roasting your code decisions ]</em>
</p>

Floating PIP with an animated stage. Themed backgrounds, chibi character sprites with idle/talking/gesturing animations, dialogue bubbles. TV characters watch your Claude Code session and explain what's happening — completely in character.

> **Gilfoyle:** A DispatchSource. It's basically a file stalker.
> **Dinesh:** So it watches files? Like my ex watches my Instagram?

8 character duos across 8 shows. Dialog adapts to your coding pace. Cold opens play instantly when Theater opens. Fillers bridge quiet moments. Voice playback via owned TTS sidecar. Non-repeatable — every cold open and filler plays exactly once, then it's gone.

Your messages get referenced as a third character from the show — you're Richard in Silicon Valley, Michael in The Office, Jerry in Rick and Morty.

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
<summary><strong>Voice playback</strong></summary>

Text-only dialog works out of the box. For character voices:

```bash
pip install autoclaw-theater
# autoclaw auto-launches the voice server when Theater Mode is active
```

First install downloads ~500MB of model weights (once). Voices are cached to `.autoclaw/voice-cache/` — cold opens play from cache with zero TTS latency. [Autoclaw Theater repo](https://github.com/sameeeeeeep/autoclaw-theater)

</details>

---

## Board

A floating kanban widget that tracks your session. Haiku maintains it as a PM agent — moving completed work to Done, surfacing new todos based on session context.

- **Add** a prediction to the board for later
- **Tap** any board item to inject it at your cursor + clipboard
- **+** on any transcript to save it as a todo

Toggle from the toast header. Lives at bottom-left, Theater lives at bottom-right.

---

## Four modes

Autoclaw is a four-mode ambient AI layer. Each mode adds a new capability:

| Mode | What it does | Status |
|------|-------------|--------|
| **Transcribe** | Voice-to-text, predictions, smart enhance, theater, board | **Shipping** |
| **Analyze** | Watches your screen, detects friction, offers to help before you ask | Built |
| **Task** | Speak or paste a command, Claude handles it with full MCP access | Built |
| **Learn** | Do something once, Claude extracts a reusable template | Built |

---

## Quick start

```bash
git clone https://github.com/sameeeeeeep/autoclaw.git
cd autoclaw
make run
```

**Requirements:** macOS 14+, Claude Code CLI, Xcode 15+. Grant Accessibility + Microphone when prompted.

**Optional:**
```bash
ollama pull qwen2.5:3b          # local bouncer for Analyze mode
pip install autoclaw-theater     # Theater mode voice playback
```

---

## Controls

| Key | Action |
|-----|--------|
| **Fn** | Open toast / start recording / stop recording |
| **Right Shift** | Cycle modes |
| **Left Option x2** | Full dismiss |
| **Option + Z** | Dismiss toast, keep session |
| **Option + X** | Cycle sub-mode |

---

## Build

| | |
|---|---|
| `make` / `make spm` | Release build (SPM + WhisperKit) |
| `make debug` | Fast iteration |
| `make legacy` | No WhisperKit, Apple Speech fallback |
| `make dmg` | Distributable DMG |
| `make run` | Build + launch |

---

## Under the hood

54 Swift files. WhisperKit on Neural Engine. Persistent Haiku sessions via Claude CLI. JSONL file watcher with 4s debounce. Session tempo tracking. Voice caching. PM agent with sandboxed file access. Liquid glass UI on macOS 26 Tahoe.

Full architecture, sensor pipeline, file inventory, and every design decision in [CLAUDE.md](CLAUDE.md).

---

<p align="center">
  <a href="https://thelastprompt.ai">The Last Prompt</a> · <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <em>You think it. You say it. Claude builds it.</em>
</p>
