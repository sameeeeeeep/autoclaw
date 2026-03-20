# Autoclaw

**Ambient AI for macOS.** An AI agent that lives at the OS layer — not inside an app. It sees your screen, understands what you're doing, detects friction in your workflow, and offers to fix it. You just approve.

Built by [The Last Prompt](https://thelastprompt.ai) — a mission to write the last prompt that makes prompting obsolete.

---

## The Problem

Every AI tool today lives *inside* an app. You copy context out of one app, paste it into a chatbot, figure out the right prompt, get a result, then manually carry it back. The human is the integration layer. The human is the bottleneck.

## The Idea

What if AI operated at the **interface level** — watching everything you do across every app, understanding your intent, and acting on your behalf? Not another app to switch to. An ambient layer that already knows what you need.

Autoclaw is the first implementation of **ARIA** (Agentic Reality Interface Architecture): AI as the interface to your computer, not as a chatbot within it.

---

## How It Works

```
You work normally on your Mac
        │
        ▼
┌─────────────────────────────────────────────────┐
│  Perception Layer                               │
│                                                 │
│  Screen capture ──→ Neural Engine embeddings    │
│  Active window  ──→ Web app resolution          │
│  Clipboard      ──→ Content classification      │
│  File system    ──→ FSEvents monitoring         │
│  Clicks         ──→ Interaction tracking        │
└───────────────────────┬─────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────┐
│  Intelligence Layer (ARIA)                      │
│                                                 │
│  Key frames sent to Sonnet ──→ visual context   │
│  Friction detector ──→ spots manual workflows   │
│  Capability map ──→ what's automatable          │
│  Capability discovery ──→ what could be         │
└───────────────────────┬─────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────┐
│  "You're copying prices from Amazon into a      │
│   spreadsheet. I can pull those directly."       │
│                                                 │
│                    [ Do it ]  [ Dismiss ]        │
└─────────────────────────────────────────────────┘
```

**You never prompted it.** It saw what you were doing, recognized the friction, checked what tools it has, and offered to help. You just approve or ignore.

---

## ARIA Intelligence

The core of Autoclaw isn't a chatbot — it's a perception-to-action pipeline that runs continuously while you work.

### Friction Detection
Watches your live activity stream and recognizes patterns that signal manual work:
- **Cross-app transfers** — copying data from one app and pasting into another
- **File shuttles** — downloading from one service, uploading to another
- **Manual lookups** — switching to a reference app, copying a value, switching back
- **Repetitive navigation** — the same app-switching loop happening over and over

### Key Frame Analysis
Instead of noisy OCR, Autoclaw uses **Apple's Neural Engine** (VNGenerateImageFeaturePrintRequest) to embed screen frames as 768-dim vectors and detect when something actually changed semantically. Only meaningful frames get sent to **Sonnet's vision** — with active window crops at 1440px for real detail. It doesn't just see "Chrome." It sees "editing row 3 of Q1 Budget in Google Sheets."

Ported from [video2ai](https://github.com/sameeeeeeep/video2ai)'s key frame extraction — the same cosine distance + adaptive thresholding approach, applied to live screen capture instead of video files.

### Capability Matching
When friction is detected, Autoclaw checks its **capability map** — an index of every installed MCP tool and what it can do. If an installed tool can solve the friction, it offers immediately. If not, it searches the web for MCP servers that could.

### Web App Resolution
Knows that "Chrome" isn't Chrome — it's Notion, Figma, Gmail, Jira, whatever the URL says. This is how "user switched from Chrome to Chrome" becomes "user switched from Notion to Google Sheets."

---

## When You Do Want to Talk

Autoclaw also has direct interaction modes for when you want to ask or command:

| Mode | What it does |
|------|-------------|
| **Task** | Execute — edit files, run commands, ship code |
| **Question** | Ask — queries meetings, tasks, web. Never touches code |
| **Analyze** | Deep read — structured assessment without changes |
| **Add to Tasks** | Create ClickUp tasks from context |

Cycle modes with **Option+X**. Each mode runs a dedicated Claude Code skill that enforces the right behavior.

---

## Connectors

Autoclaw spawns Claude Code sessions with access to your MCP servers:

| Connector | What it provides |
|-----------|-----------------|
| **ClickUp** | Tasks, time tracking, comments |
| **Granola** | Meeting notes, transcripts, action items |
| **Google Sheets** | Spreadsheet read/write |
| **GitHub** | Issues, PRs, repos |
| **Web Search** | Real-time information |
| **Filesystem** | Project files (Task mode only) |

Add any MCP server to `~/.claude/mcp.json` and Autoclaw can use it — both for direct execution and for capability matching against detected friction.

---

## Keyboard

| Shortcut | Action |
|----------|--------|
| **Fn** | Toggle session / pause / resume |
| **Double-tap Left Option** | End session |
| **Option+Z** | Capture screenshot |
| **Option+X** | Cycle request mode |

---

## Tech

- **Swift** — native macOS, no Electron
- **SwiftUI** — toast, panel, pill widget
- **Apple Vision / Neural Engine** — frame embeddings for change detection
- **Claude Code CLI** — stream-json execution
- **MCP** — connector ecosystem
- **Claude Code Skills** — per-mode behavior enforcement

## Setup

```bash
git clone https://github.com/sameeeeeeep/autoclaw.git
cd autoclaw
make run
```

**Requires:** macOS 13+, [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), Anthropic API key. Grant Accessibility permission for global hotkeys.

---

## Project Structure

```
Sources/
│   Perception
├── ScreenCaptureStream.swift  — screen capture + active window cropping + click detection
├── ActiveWindowService.swift  — app/window/URL tracking with web app resolution
├── ClipboardMonitor.swift     — clipboard polling
├── ScreenOCR.swift            — Apple Vision OCR with cursor proximity ranking
├── FileActivityMonitor.swift  — FSEvents watcher for cross-app file transfers
├── WorkflowRecorder.swift     — passive always-on event recording
│
│   ARIA Intelligence
├── KeyFrameAnalyzer.swift     — Neural Engine embeddings + Sonnet vision analysis
├── FrictionDetector.swift     — pattern matching on live activity stream
├── CapabilityMap.swift        — indexes installed MCP tools into searchable registry
├── CapabilityDiscovery.swift  — web search for new integrations
├── WebAppResolver.swift       — browser URLs → semantic app identities
│
│   Execution
├── ClaudeCodeRunner.swift     — stream-json CLI integration
├── TaskDeductionService.swift — task analysis and intent extraction
│
│   Interface
├── PillView.swift             — menu bar pill with intelligence glow
├── TaskApprovalView.swift     — toast UI with session thread
├── MainPanelView.swift        — panel with home, threads, settings
├── AppState.swift             — central state and ARIA wiring
└── ...
```

---

## The Last Prompt

Autoclaw is Phase 1 of [The Last Prompt](https://thelastprompt.ai)'s vision:

> Always-on intelligence that understands the user's world, extracts tasks for work and life, figures out the capability required to fulfil each task, builds it if it doesn't exist, and fulfils the tasks — without the need to prompt it.

AI shouldn't live in an app. It should be the interface.

---

*Built with Claude Code. Powered by ARIA.*
