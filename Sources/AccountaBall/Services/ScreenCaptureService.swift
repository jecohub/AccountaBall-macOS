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
