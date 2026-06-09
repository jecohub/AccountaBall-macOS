import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 96, height: 96)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func positionNearTopRight() {
        guard let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.maxX - frame.width - 20
        let y = screen.visibleFrame.maxY - frame.height - 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func resize(for phase: AppPhase) {
        switch phase {
        case .idle, .welcome:
            setContentSize(clampedToScreen(NSSize(width: 400, height: 320))); center()
        case .setup:
            // Taller so the task rows + "you did this before" cards have room; the
            // view also scrolls and pins "Let's go!", and this is clamped to the
            // screen so the panel can never exceed the display.
            setContentSize(clampedToScreen(NSSize(width: 520, height: 580))); center()
        case .session:
            // Small widget peeking at the right edge — does NOT cover the screen,
            // so the rest of the desktop stays clickable.
            anchorRightEdge(size: NSSize(width: 130, height: 170))
        case .whatsUp:
            // "What's up?" card with the two option buttons, near the ball.
            anchorRightEdge(size: NSSize(width: 300, height: 300))
        case .ambiguous:
            // Same sizing as .offTask — Task 8's AmbiguousAskView is a comparable
            // centered alert card.
            setContentSize(clampedToScreen(NSSize(width: 360, height: 420))); center()
        case .offTask:
            // Compact centered alert card (the view draws a fixed-width rounded
            // card that hugs its content). The old quarter-screen side panel left
            // the small verdict cards — "Carry on", etc. — lost in a black slab.
            setContentSize(clampedToScreen(NSSize(width: 360, height: 420))); center()
        case .progress:
            setContentSize(clampedToScreen(NSSize(width: 480, height: 420))); center()
        case .aiUnavailable:
            // Centered alert card. The view draws a fixed-width rounded card; the
            // panel just needs enough room for the tallest hint (the Ollama
            // setup hint wraps to a few lines) and centers it on screen.
            setContentSize(clampedToScreen(NSSize(width: 340, height: 380))); center()
        case .complete:
            setContentSize(clampedToScreen(NSSize(width: 600, height: 560))); center()
        case .freeBall:
            // Small calm ball peeking at the edge, like .session.
            anchorRightEdge(size: NSSize(width: 130, height: 170))
        case .freeBallLog:
            // Compact centered card: timer + End Session.
            setContentSize(clampedToScreen(NSSize(width: 300, height: 260))); center()
        case .freeBallRecap:
            // Roomy centered recap card (narrative + bars + insight).
            setContentSize(clampedToScreen(NSSize(width: 520, height: 540))); center()
        case .freeBallHistory:
            // Past-sessions list.
            setContentSize(clampedToScreen(NSSize(width: 460, height: 560))); center()
        }
    }

    /// The allowance "still counts?" confirm card is shown over the session ball
    /// but needs far more room than the tiny session widget (130×170) — without
    /// this it clips the title and buttons. Size it like the other session-area
    /// prompt cards, anchored near where the ball sits.
    func resizeForAllowanceConfirm() {
        anchorRightEdge(size: NSSize(width: 320, height: 320))
    }

    /// Clamp a requested content size to the current screen's visible frame (with
    /// a margin) so a panel can never grow past the display and push controls off
    /// the visible area.
    private func clampedToScreen(_ size: NSSize, margin: CGFloat = 40) -> NSSize {
        guard let vf = NSScreen.main?.visibleFrame else { return size }
        return NSSize(width: min(size.width, vf.width - margin),
                      height: min(size.height, vf.height - margin))
    }

    /// Pin the panel flush against the right edge of the visible screen, vertically centered.
    private func anchorRightEdge(size: NSSize) {
        setContentSize(clampedToScreen(size))
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.maxX - frame.width
        let y = vf.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
