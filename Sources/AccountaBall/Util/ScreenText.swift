import Foundation

/// Build the text we OCR from one capture tick: the focused window in full
/// (primary), plus a truncated pass over the whole screen as lighter peripheral
/// context. With no focused window, the full screen is the only signal. Shared by
/// AccountabilityEngine (classify input) and FreeBallEngine (stored transcript).
func buildScreenText(from frame: CapturedFrame, ocr: OCRService,
                     peripheralChars: Int = AppConstants.peripheralScreenChars) async -> String {
    guard let focused = frame.focused else {
        return await ocr.extractText(from: frame.full)
    }
    let primary = await ocr.extractText(from: focused)
    let full = await ocr.extractText(from: frame.full)
    let light = String(full.prefix(peripheralChars))
    if primary.isEmpty { return light }
    if light.isEmpty { return primary }
    return "Active window:\n\(primary)\n\nAlso visible on screen:\n\(light)"
}
