# Autoclaw

**Ambient AI for macOS.** An AI agent that lives at the OS layer — not inside an app. It sees your screen, understands what you're doing, detects friction in your workflow, and offers to fix it. You just approve.

Built by [The Last Prompt](https://thelastprompt.ai) — a mission to write the last prompt that makes prompting obsolete.

> This is early-stage, open-source, and actively developed. Contributions welcome.

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
│  Clicks         ──→ OCR + interaction tracking  │
│  Chrome ext     ──→ DOM events (selectors, vals)│
└───────────────────────┬─────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────┐
│  Intelligence Layer (ARIA)                      │
│                                                 │
│  60s frame grids ──→ Haiku vision analysis      │
│  Friction detector ──→ spots manual workflows   │
│  Capability map ──→ what's automatable          │
│  Workflow matcher ──→ recognizes learned flows   │
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

## Three Modes

| Mode | What happens | What runs |
|------|-------------|-----------|
| **Ambient** | Passive observation. ARIA watches your screen, detects friction, recognizes learned workflows, offers help. | FrictionDetector + KeyFrameAnalyzer + WorkflowMatcher |
| **Learn** | You show autoclaw a workflow. It records clicks, screenshots, DOM events, and extracts structured steps with Sonnet vision. | WorkflowRecorder + Chrome Extension + WorkflowExtractor |
| **AI Search** | Direct interaction. Capture clipboard/screenshots, ask questions, execute tasks. | TaskDeductionService + Claude Code execution |

---

## Learn Mode — Teach By Doing

1. Switch to Learn mode, hit record
2. Do the workflow normally — autoclaw captures everything:
   - Mouse clicks with OCR context
   - Screenshots at key moments (Neural Engine change detection)
   - Chrome extension DOM events (exact selectors, field names, typed values)
   - Clipboard changes, app switches
3. Stop recording — Sonnet analyzes screenshots + OCR + DOM events to extract human-readable steps
4. Review, name, and save the workflow
5. Next time you start doing it, ARIA recognizes the pattern and offers to run it for you

---

## Chrome Extension

The `ChromeExtension/` directory contains a Manifest V3 extension that captures structured DOM events during Learn mode — much richer than OCR alone:

| OCR gives you | Extension gives you |
|---|---|
| `Clicked 'Co' in unknown app` | `Clicked button[aria-label="Compose"] on mail.google.com` |
| `Clicked near 'To'` | `Typed 'sameep@company.com' in input[name="to"]` |
| `Clipboard event` | `Selected 'High Priority' in select[name="priority"]` |

**Install:** `chrome://extensions` → Enable developer mode → Load unpacked → Select `ChromeExtension/` folder. It auto-connects to autoclaw via WebSocket on `ws://127.0.0.1:9849`.

---

## ARIA Intelligence

### Friction Detection
Watches your live activity stream and recognizes patterns:
- **Cross-app transfers** — copying data from one app and pasting into another
- **File shuttles** — downloading from one service, uploading to another
- **Manual lookups** — switching to a reference app, copying a value, switching back
- **Repetitive navigation** — the same app-switching loop over and over
- **Recognized workflows** — matches against previously learned workflows

### Key Frame Analysis
Uses **Apple's Neural Engine** (VNGenerateImageFeaturePrintRequest) to embed screen frames and detect meaningful visual changes. Frames are stitched into grids (max 6 per image) and sent to **Haiku** every 60 seconds for activity understanding and workflow recognition.

### Capability Matching
When friction is detected, autoclaw checks its **capability map** — an index of every installed MCP tool. If a tool can solve the friction, it offers immediately. If not, it searches for MCP servers that could.

### Web App Resolution
Knows that "Chrome" isn't Chrome — it's Notion, Figma, Gmail, Jira, whatever the URL says.

---

## Request Modes

When you want to interact directly:

| Mode | What it does |
|------|-------------|
| **Task** | Execute — edit files, run commands, ship code |
| **Question** | Ask — queries meetings, tasks, web. Never touches code |
| **Analyze** | Deep read — structured assessment without changes |
| **Add to Tasks** | Create ClickUp tasks from context |
| **Learn** | Record and extract a workflow |

Cycle modes with **Option+X**. Each mode runs a dedicated Claude Code skill.

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

Add any MCP server to `~/.claude/mcp.json` and autoclaw can use it — both for direct execution and for capability matching against detected friction.

---

## Keyboard

| Shortcut | Action |
|----------|--------|
| **Fn** | Toggle session / pause / resume |
| **Double-tap Left Option** | End session |
| **Option+Z** | Capture screenshot |
| **Option+X** | Cycle request mode |

---

## Setup

```bash
git clone https://github.com/thelastprompt/autoclaw.git
cd autoclaw
make run
```

**Requires:**
- macOS 13+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- Anthropic API key (set in autoclaw settings or `ANTHROPIC_API_KEY` env var)
- Grant Accessibility + Screen Recording permissions when prompted

**Optional:**
- Chrome extension (load unpacked from `ChromeExtension/` for richer Learn mode)

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
├── WorkflowRecorder.swift     — event recording (explicit learn + passive ambient)
│
│   ARIA Intelligence
├── KeyFrameAnalyzer.swift     — Neural Engine embeddings + Haiku vision (60s grid analysis)
├── FrictionDetector.swift     — pattern matching on live activity stream
├── CapabilityMap.swift        — indexes installed MCP tools into searchable registry
├── CapabilityDiscovery.swift  — web search for new integrations
├── WebAppResolver.swift       — browser URLs → semantic app identities
├── WorkflowMatcher.swift      — NLEmbedding similarity for workflow recognition
├── WorkflowExtractor.swift    — Claude vision extraction from recordings
│
│   Browser Integration
├── BrowserBridge.swift        — WebSocket server for Chrome extension
│
│   Execution
├── ClaudeCodeRunner.swift     — stream-json CLI integration
├── TaskDeductionService.swift — task analysis and intent extraction
│
│   Interface
├── PillView.swift             — floating pill widget with status + mode bar
├── TaskApprovalView.swift     — toast UI with session thread
├── MainPanelView.swift        — panel with home, threads, settings
├── AppState.swift             — central state and ARIA wiring
└── ...

ChromeExtension/
├── manifest.json              — Manifest V3
├── content.js                 — DOM event capture (clicks, inputs, navigation)
├── background.js              — WebSocket client + recording state management
├── popup.html/js              — Connection status popup
└── icon*.png                  — Extension icons
```

---

## Contributing

See [PLAN.md](PLAN.md) for the full roadmap of known gaps and planned work. Pick anything, open a PR.

---

## License

MIT — see [LICENSE](LICENSE).

---

## The Last Prompt

Autoclaw is Phase 1 of [The Last Prompt](https://thelastprompt.ai)'s vision:

> Always-on intelligence that understands the user's world, extracts tasks for work and life, figures out the capability required to fulfil each task, builds it if it doesn't exist, and fulfils the tasks — without the need to prompt it.

AI shouldn't live in an app. It should be the interface.

---

*Built with Claude Code. Powered by ARIA.*
