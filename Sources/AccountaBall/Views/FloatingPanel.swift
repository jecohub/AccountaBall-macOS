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
            setContentSize(NSSize(width: 400, height: 320)); center()
        case .setup:
            setContentSize(NSSize(width: 520, height: 440)); center()
        case .session:
            // Small widget peeking at the right edge — does NOT cover the screen,
            // so the rest of the desktop stays clickable.
            anchorRightEdge(size: NSSize(width: 130, height: 170))
        case .whatsUp:
            // "What's up?" card with the two option buttons, near the ball.
            anchorRightEdge(size: NSSize(width: 300, height: 300))
        case .offTask:
            // A side panel taking ~1/4 of the screen width (not a full-screen takeover).
            if let vf = NSScreen.main?.visibleFrame {
                anchorRightEdge(size: NSSize(width: vf.width * 0.25, height: vf.height * 0.6))
            } else {
                anchorRightEdge(size: NSSize(width: 360, height: 420))
            }
        case .progress:
            setContentSize(NSSize(width: 480, height: 420)); center()
        case .aiUnavailable:
            anchorRightEdge(size: NSSize(width: 300, height: 300))
        case .complete:
            setContentSize(NSSize(width: 600, height: 500)); center()
        }
    }

    /// Pin the panel flush against the right edge of the visible screen, vertically centered.
    private func anchorRightEdge(size: NSSize) {
        setContentSize(size)
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.maxX - frame.width
        let y = vf.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
