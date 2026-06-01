# Src

Layer 2 context for /src workspace.

## Purpose
Swift application code for AccountaBall — macOS 13+ floating accountability widget.

## Code Conventions
- One file per type, filename matches the primary type
- `@MainActor` on all SwiftUI views and anything touching UI
- Capture + AI work in `Task { }` blocks off main thread
- No force unwraps — use `guard let` or `if let`
- Prefer `async/await` over callbacks for all network and capture work

## Testing Requirements
- Unit tests for: state machine transitions, OCR text parsing, AI response parsing
- Integration tests are manual (capture and AI require real permissions)
- Test framework: XCTest (built-in)

## Standard Libraries / Frameworks
- SwiftUI (UI)
- AppKit / NSPanel (floating window)
- ScreenCaptureKit (screen capture, macOS 13+)
- Vision.framework (OCR)
- Foundation / URLSession (Claude API HTTP calls)

## Key Files to Create (Phase 1)
- `AccountaBallApp.swift` — app entry point, NSApplicationDelegate
- `FloatingPanel.swift` — NSPanel subclass, always-on-top config
- `BallView.swift` — SwiftUI smiling ball widget
- `TaskInputView.swift` — text field for declaring the current task
- `AppState.swift` — @Observable state: currentTask, ballState, sessionLog

## Key Files to Create (Phase 2+)
- `ScreenCaptureService.swift` — ScreenCaptureKit loop
- `OCRService.swift` — Vision.framework text extraction
- `AIService.swift` — Claude API / Ollama protocol + implementations
- `AccountabilityEngine.swift` — orchestrates capture → OCR → AI → state update

## Inputs
- Layer 0: ../CLAUDE.md

## Output Locations
- Views → Views/
- Services → Services/
- Models → Models/
