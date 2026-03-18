# Autoclaw

**An ambient AI agent that lives in your macOS menu bar.** It observes your world, understands your needs, and fulfils them — without requiring you to prompt it.

Built by [The Last Prompt](https://thelastprompt.ai) — a mission to write the last prompt that leads to singularity.

---

## What is Autoclaw?

Autoclaw is a macOS menu bar app that brings always-on intelligence to your desktop. Instead of switching between AI apps, copy-pasting context, and figuring out which tool to use — Autoclaw watches your clipboard, understands what you're working on, and acts on your behalf.

**The core insight:** AI within apps creates cognitive load. Users have to figure out *what* to use, *when* to use it, *how* to use it, and then actually use it. Humans become the bottleneck. Autoclaw removes that friction by bringing agentic capability to the **interface level** — not to more apps, but to the layer where you already work.

## Architecture: ARIA

**Agentic Reality Interface Architecture** — Autoclaw is the first implementation of ARIA, a pattern where AI agents operate at the OS interface layer rather than inside individual applications.

```
┌─────────────────────────────────────────────┐
│  Your Desktop                               │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐       │
│  │Slack │ │Chrome│ │VS    │ │Mail  │ ...    │
│  │      │ │      │ │Code  │ │      │       │
│  └──────┘ └──────┘ └──────┘ └──────┘       │
│         ▲           ▲           ▲           │
│         │  clipboard │  context  │           │
│         └─────┬──────┴─────┬─────┘           │
│               ▼            ▼                 │
│  ┌─────────────────────────────────────┐     │
│  │  Autoclaw (menu bar)               │     │
│  │  ┌─────────┐  ┌──────────────────┐ │     │
│  │  │ Observe │→│ Understand → Act  │ │     │
│  │  └─────────┘  └──────────────────┘ │     │
│  │         ↕            ↕              │     │
│  │  ┌──────────────────────────────┐   │     │
│  │  │ Connectors (MCP)            │   │     │
│  │  │ ClickUp · Granola · Sheets  │   │     │
│  │  │ GitHub · Web · Filesystem   │   │     │
│  │  └──────────────────────────────┘   │     │
│  └─────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

## Features

### Session-Based Workflow
- **Start a session** with Fn key or from the menu bar
- Autoclaw monitors your clipboard, active app, and window context
- Copy anything — code, text, URLs, error messages — and it appears in the session thread
- **End session** with double-tap Left Option; **resume** with Fn

### Request Modes (cycle with Option+X)
| Mode | Icon | What it does |
|------|------|-------------|
| **Task** | Play | Execute a coding/automation task — edit files, run commands, ship code |
| **Add to Tasks** | Plus | Create ClickUp tasks from context — meetings, bugs, ideas |
| **Question** | Question | Ask anything — queries Granola meetings, ClickUp tasks, web search. Never touches code |
| **Analyze** | Magnifier | Deep analysis of context — read code, check tools, provide structured assessment without making changes |

Each mode invokes a dedicated Claude Code **skill** (`~/.claude/skills/autoclaw-*/SKILL.md`) that enforces the right behavior — Question mode is forbidden from exploring the filesystem, Task mode is told to execute autonomously, etc.

### Toast UI
- Floating toast window with live session thread
- **Apple Intelligence-style glow** reflects state: green (active), white (paused), purple (processing), cyan (done)
- Menubar icon in the header changes color with session state
- Live streaming execution output directly in the toast
- Model and project selectors in the header
- Screenshot capture (Option+Z), file drag & drop
- Session-ended state with Resume/Dismiss

### Connectors (via MCP)
Autoclaw spawns Claude Code sessions that have access to all your configured MCP servers:

| Connector | What it provides |
|-----------|-----------------|
| **ClickUp** | Task management — create, search, update tasks, time tracking, comments |
| **Granola** | Meeting intelligence — notes, transcripts, decisions, action items |
| **Google Sheets** | Spreadsheet data — read, write, analyze |
| **GitHub** | Code — issues, PRs, repo management |
| **Web Search** | Real-time information retrieval |
| **Filesystem** | Read, write, edit project files (Task mode only) |

Add any MCP server to `~/.claude/mcp.json` and Autoclaw can use it.

### Keyboard-Driven
| Shortcut | Action |
|----------|--------|
| **Fn** | Toggle pause / resume session / start session |
| **Double-tap Left Option** | End session (or dismiss ended toast) |
| **Option+Z** | Capture screenshot to thread |
| **Option+X** | Cycle request mode |

### Panel
- Main panel with Home, Threads, and Settings tabs
- Session history — click any past session to view details
- Project management — multiple projects with per-project sessions
- Model selection — Haiku, Sonnet, Opus

## Use Cases

**Developer workflow:**
Copy an error from your terminal → Autoclaw captures it → switch to Task mode → hit Enter → it fixes the bug in your codebase.

**Meeting follow-ups:**
After a standup → switch to Question mode → "what action items came out of the standup?" → Autoclaw queries Granola → then switch to Add to Tasks → "create tasks for those action items" → ClickUp tasks created.

**Research & context:**
Copy a Slack message about a bug → switch to Analyze mode → "what's the root cause?" → Autoclaw reads the relevant code and provides analysis without changing anything.

**Quick answers:**
"How many open tasks does the mobile team have?" → Question mode → queries ClickUp → answers in seconds, never touches the filesystem.

## Tech Stack

- **Swift** — native macOS app, no Electron
- **SwiftUI** — toast, panel, and pill widget UI
- **Claude Code CLI** — stream-json I/O for real-time execution
- **MCP (Model Context Protocol)** — connector ecosystem
- **Claude Code Skills** — per-mode behavior enforcement

## Setup

### Prerequisites
- macOS 13+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (`npm install -g @anthropic-ai/claude-code`)
- Anthropic API key or OAuth token

### Build & Run
```bash
git clone https://github.com/thelastprompt/autoclaw.git
cd autoclaw
make run
```

### Configure
1. Open Autoclaw from the menu bar → Settings
2. Add your Anthropic API key
3. Add a project (name + path to a local directory)
4. Configure MCP servers in `~/.claude/mcp.json` for ClickUp, Granola, etc.
5. Grant Accessibility permission (System Settings → Privacy & Security → Accessibility) for global hotkeys

## Project Structure

```
Sources/
├── App.swift                 # App entry point
├── AppDelegate.swift         # Menu bar, window management, state observation
├── AppState.swift            # Central state — sessions, modes, execution
├── ClaudeCodeRunner.swift    # Stream-json CLI integration
├── TaskDeductionService.swift # Haiku-based task analysis
├── TaskApprovalView.swift    # Toast UI — thread, input, mode selector
├── MainPanelView.swift       # Panel — home, threads, settings
├── PillView.swift            # Side widget with intelligence glow
├── GlobalHotkeyMonitor.swift # Fn, Option, keyboard shortcuts
├── SessionThread.swift       # Session persistence
└── ...
```

## The Last Prompt

Autoclaw is Phase 1 of [The Last Prompt](https://thelastprompt.ai)'s ambient AI vision:

> We're building always-on intelligence that understands the user's world, extracts tasks for work and life, figures out the capability required to fulfil each task, builds it if it doesn't exist, and fulfils the tasks — without the need to prompt it.

**Phase 1: macOS** — Autoclaw is an AI ghost that lives on your MacBook menu bar. It observes your world, understands your needs, and fulfils them for you.

---

*Built with Claude Code. Powered by ARIA.*
