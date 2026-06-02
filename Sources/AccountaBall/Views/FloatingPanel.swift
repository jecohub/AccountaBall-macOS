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
        let size: NSSize
        switch phase {
        case .idle, .welcome:        size = NSSize(width: 400, height: 320)
        case .setup:                 size = NSSize(width: 520, height: 440)
        case .session, .offTask:     size = NSSize(width: 0, height: 0)  // transparent overlay
        case .progress:              size = NSSize(width: 480, height: 420)
        case .complete:              size = NSSize(width: 600, height: 500)
        }
        if phase == .session || phase == .offTask {
            // Full screen transparent overlay for edge widget
            if let screen = NSScreen.main {
                setFrame(screen.frame, display: true, animate: true)
            }
        } else {
            setContentSize(size)
            center()
        }
    }
}
