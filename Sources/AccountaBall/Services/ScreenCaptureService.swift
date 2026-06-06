import Foundation
import ScreenCaptureKit
import AppKit

/// One capture tick: the frontmost window (primary signal — the content the user
/// is actually in) plus the whole display (a lighter, peripheral signal). When no
/// focused window is identified, `focused` is nil and `full` is the only signal.
struct CapturedFrame {
    let focused: CGImage?
    let full: CGImage
}

class ScreenCaptureService {
    func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// Capture both the frontmost app's focused window (primary) and the full
    /// display (lighter secondary). OCR reads the focused window in full and uses
    /// a truncated pass over the display for peripheral context — so the active
    /// content drives classification but a relevant reference in another window
    /// still registers.
    func captureFrame(excluding panelTitle: String? = nil) async throws -> CapturedFrame? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else { return nil }

        // Full display (lighter secondary signal), excluding our own panel.
        let excludedWindows = panelTitle.map { title in
            content.windows.filter { $0.title == title }
        } ?? []
        let fullConfig = SCStreamConfiguration()
        fullConfig.width = Int(display.width)
        fullConfig.height = Int(display.height)
        fullConfig.captureResolution = .nominal
        guard let full = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: excludedWindows),
            configuration: fullConfig
        ) else { return nil }

        // Frontmost window (primary signal), if we can identify one.
        var focused: CGImage? = nil
        if let window = frontmostWindow(in: content, excludingTitle: panelTitle) {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.captureResolution = .nominal
            focused = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            )
        }

        return CapturedFrame(focused: focused, full: full)
    }

    /// The frontmost application's main content window (largest on-screen window
    /// it owns), or nil if the active app is our own panel or has no suitable
    /// window — in which case the caller falls back to a full-display capture.
    private func frontmostWindow(in content: SCShareableContent, excludingTitle: String?) -> SCWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        // Don't focus on ourselves (e.g. when the user clicks into the off-task
        // prompt) — that would capture the AccountaBall panel, not their work.
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return content.windows
            .filter { w in
                w.isOnScreen
                    && w.title != excludingTitle
                    && w.owningApplication?.bundleIdentifier == frontApp.bundleIdentifier
                    && w.frame.width >= 200 && w.frame.height >= 200
            }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func startLoop(
        interval: TimeInterval = 5,
        panelTitle: String? = nil,
        onCapture: @escaping (CapturedFrame) async -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                if let frame = try? await captureFrame(excluding: panelTitle) {
                    await onCapture(frame)
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
