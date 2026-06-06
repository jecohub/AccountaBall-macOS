import Foundation
import ScreenCaptureKit
import AppKit

class ScreenCaptureService {
    func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    func captureScreen(excluding panelTitle: String? = nil) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else { return nil }

        // Prefer the frontmost app's focused window so OCR reads the content the
        // user is actually working in (e.g. the page inside the browser) instead
        // of the entire desktop — the menu bar, dock, every other window, and all
        // the browser chrome/tabs that drown out the real signal. Fall back to the
        // whole display if we can't identify a suitable window.
        if let window = frontmostWindow(in: content, excludingTitle: panelTitle) {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.captureResolution = .nominal
            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            ) {
                return image
            }
            // fall through to full-display capture on failure
        }

        let excludedWindows = panelTitle.map { title in
            content.windows.filter { $0.title == title }
        } ?? []

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.captureResolution = .nominal

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
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
        onCapture: @escaping (CGImage) async -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                if let image = try? await captureScreen(excluding: panelTitle) {
                    await onCapture(image)
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
