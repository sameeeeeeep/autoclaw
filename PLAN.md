# Autoclaw — Development Plan

Everything that needs to be built, fixed, or improved. Organized by priority.

---

## P0 — Core Value (blocks the product from working)

### Workflow Browser & Management UI
The entire learn→save→replay loop is broken at "see what you saved." Saved workflows are invisible.

- [ ] New tab in MainPanelView: "Workflows" — list all saved workflows
- [ ] Show workflow details: name, steps, tools, estimated time, run count, last run
- [ ] Rename workflows inline
- [ ] Delete workflows with confirmation
- [ ] Re-run a workflow from the browser (one-click execution)
- [ ] View step details — each step's description, tool, estimated time
- [ ] Edit extracted steps — reorder, delete, modify descriptions (TODO exists in code)
- [ ] Manual step creation — add steps without recording
- [ ] Workflow preview/dry-run — show what would happen without executing

### Thread Message Persistence
Past sessions show "Session messages aren't persisted yet." All conversation history is lost on restart.

- [ ] Serialize threadMessages to disk alongside SessionStore
- [ ] Load past thread messages when viewing historical sessions
- [ ] Message search across all sessions
- [ ] Conversation export (markdown, JSON)

### Learn Mode Extraction Quality
Extraction runs but results are often garbage. The pipeline needs validation.

- [ ] Verify Claude CLI `-p` mode actually passes images to the model (confirmed working with `--dangerously-skip-permissions`)
- [ ] Test extraction end-to-end with Chrome extension DOM events
- [ ] Test extraction with screenshots only (native app workflows)
- [ ] Compare extraction quality: OCR-only vs screenshots+OCR vs DOM events+screenshots
- [ ] Add extraction quality scoring — let Sonnet rate its own confidence per step
- [ ] Retry extraction with different models if quality is low

### Fix "Unknown App" in Recordings
ActiveWindowService provides app names but they don't always reach the recorder.

- [ ] Audit the full chain: ActiveWindowService → AppState → WorkflowRecorder
- [ ] Ensure app name is always resolved before events are recorded
- [ ] WebAppResolver integration — "Chrome" → "Gmail", "Notion", etc.
- [ ] Test with 10+ common apps and web apps

---

## P1 — Significant UX Gaps

### ARIA Visibility & Control
Friction detection runs silently. Users don't know it exists.

- [ ] Connection/status indicator in pill: ARIA active/inactive dot
- [ ] Chrome extension connection indicator (green/red dot in pill)
- [ ] Friction detection history — show past detected patterns
- [ ] Capability browser — show what MCP tools are installed and what they can do
- [ ] Settings for ARIA: enable/disable friction detection, adjust sensitivity
- [ ] Settings for learn mode: screenshot frequency, OCR context radius
- [ ] Feedback on dismissed friction offers — "not useful" vs "wrong timing" vs "already doing it"

### UI Elements That Are Fake
Multiple UI elements exist visually but aren't wired to anything.

- [ ] **Triple status row** (mic, brain, code buttons) — `micOn`, `analysisOn`, `codeOn` are `@State` local to PillView, not connected to AppState. Either wire them or remove them.
- [ ] **Screen share button** — `screenShareOn` toggles an icon but does nothing. Either implement or remove.
- [ ] **PillMode.aiSearch** — switching to this mode changes nothing. Either implement distinct behavior or merge with ambient.
- [ ] **Waveform visualization** — uses `CGFloat.random()`, not actual audio levels. Wire to VoiceService audio levels or show a static indicator.

### File Monitor Scope
FileActivityMonitor watches ~/Desktop, ~/Downloads, ~/Documents, and /tmp. This is too broad.

- [ ] Remove ~/Desktop and ~/Downloads from default watched paths (unnecessary noise, triggers permission dialogs)
- [ ] Only watch project directories + /tmp (for autoclaw's own files)
- [ ] Make watched paths configurable in settings
- [ ] Already fixed: skip own keyframe/grid files to prevent infinite loops

### Settings Expansion
Settings page only has API key and projects. Missing everything else.

- [ ] Default model preference (don't have to pick every time)
- [ ] Voice settings (language, sensitivity)
- [ ] ARIA settings (enable/disable, sensitivity, cooldown)
- [ ] Chrome extension settings (WebSocket port, enable/disable)
- [ ] Privacy settings (what data is sent to Claude, local-only mode)
- [ ] Cost tracking (show API spend per session)
- [ ] Data export/import (backup workflows, sessions)
- [ ] Hotkey customization

### Learn Mode Should Suppress Ambient Recognition
During learn mode recording, FrictionDetector still runs and can surface "I recognized this workflow!" — confusing when the user is actively teaching a new one.

- [ ] Suppress friction detection while `isLearnRecording == true`
- [ ] Suppress workflow recognition suggestions during learn mode
- [ ] Resume ambient detection when recording stops

---

## P2 — Important But Not Blocking

### Error Handling & Recovery
- [ ] Meaningful error messages (not just "CLI exited 1:")
- [ ] API key validation on entry (test call to verify it works)
- [ ] Graceful handling of missing Claude CLI
- [ ] Learn recording recovery after crash (checkpoint to disk periodically)
- [ ] Execution cancellation UI (stop button, not just hotkey)
- [ ] Rate limiting for Haiku calls (60s window analysis can add up)

### Project Management
- [ ] Project renaming
- [ ] Project path editing
- [ ] Show CLAUDE.md summary in project details
- [ ] Project statistics (session count, workflow count, total time)
- [ ] Pin/favorite projects

### Onboarding
- [ ] First-run wizard: API key → grant permissions → select project → quick tutorial
- [ ] Hotkey reference card (always accessible, not buried in settings)
- [ ] Sample workflows to demonstrate learn mode
- [ ] ARIA explanation — "here's what autoclaw is doing in the background"

### Chrome Extension Reliability
- [ ] Auto-reconnect is fragile — MV3 service workers die after 30s idle
- [ ] Keepalive ping added (20s) but needs testing under real conditions
- [ ] Handle multiple Chrome windows/profiles
- [ ] Extension popup should show event count and last event timestamp
- [ ] Consider native messaging instead of WebSocket for reliability

---

## P3 — Polish & Future

### Workflow Execution Engine
Currently saved workflows just invoke a Claude Code skill. Need proper replay.

- [ ] Step-by-step execution with progress indicator
- [ ] Per-step approval mode (approve each step before it runs)
- [ ] Chrome extension replay — use saved CSS selectors to click/type
- [ ] Parameterized workflows — "compose email to {recipient} about {topic}"
- [ ] Workflow chaining — run workflow A then workflow B
- [ ] Execution history per workflow

### macOS Accessibility API Integration
For native apps (outside Chrome), the Accessibility API would give much richer data than OCR.

- [ ] AXUIElement observer for click targets (exact button titles, not OCR guesses)
- [ ] Form field labels and values via AX
- [ ] Menu item paths (File > Export > PDF)
- [ ] Window hierarchy and focused element role
- [ ] This is the native-app equivalent of what the Chrome extension does for web

### Advanced Intelligence
- [ ] Multi-workflow recognition — detect when user is combining parts of multiple workflows
- [ ] Workflow variants — same base workflow with different parameters
- [ ] Time-of-day patterns — "you do this every morning at 9am"
- [ ] Cross-session learning — patterns that span multiple sessions
- [ ] Feedback loop — execution results improve future recognition
- [ ] Cost-aware model selection — use Haiku for recognition, Sonnet only for extraction

### Platform
- [ ] Menu bar icon with quick actions
- [ ] Notification center integration
- [ ] Spotlight integration (search workflows)
- [ ] Shortcuts.app integration (trigger workflows from system shortcuts)
- [ ] Auto-update mechanism

---

## Architecture Notes

### Mode Responsibilities (what should run when)

| Component | Ambient | Learn | AI Search |
|-----------|---------|-------|-----------|
| FrictionDetector | ON | OFF (suppress) | OFF |
| KeyFrameAnalyzer | ON (60s grids → Haiku) | ON (screenshots for extraction) | OFF |
| WorkflowMatcher | ON (via Haiku) | OFF | OFF |
| WorkflowRecorder | Passive mode | Explicit mode | OFF |
| BrowserBridge | Listening | Recording | OFF |
| CapabilityMap | ON | Referenced at extraction | Referenced at deduction |
| TaskDeductionService | OFF | OFF | ON |

### Data Flow

```
Chrome Extension ──ws──→ BrowserBridge ──→ AppState.browserEventBuffer
                                              │
Screen Capture ──→ KeyFrameAnalyzer           │
      │               │                       │
      │          60s grid → Haiku             │
      │               │                       │
      │        workflow match?                │
      │               │                       │
OCR + Clicks ──→ WorkflowRecorder ──────────→ WorkflowExtractor
                                                │
                                          Sonnet vision
                                                │
                                          [Structured Steps]
                                                │
                                          WorkflowStore (persisted)
                                                │
                            FrictionDetector ←──┘ (ambient recognition)
```

---

*Last updated: March 2026*
