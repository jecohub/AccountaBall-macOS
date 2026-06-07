import Foundation

/// App-wide constants shared across the engine and utilities so values that
/// must stay in lockstep can't drift apart.
enum AppConstants {
    /// The capture/classify cycle length. The capture loop fires on this
    /// interval, each on-task cycle credits this many seconds to the task's
    /// `timeOnTask`, and the timeline coalescer extends the last range by it.
    /// 3s keeps the checking responsive (e.g. noticing you've returned to work
    /// during an off-task prompt) without hammering the model.
    static let cycleSeconds: TimeInterval = 3

    /// How many characters of the full-screen OCR to keep as the lighter,
    /// peripheral signal alongside the focused window's full text. Caps the
    /// secondary so the whole desktop can't drown out the active content.
    static let peripheralScreenChars: Int = 500

    /// Grace breather granted by the off-task "Continue anyway" escape hatch.
    /// Longer than the default settle window so a user who chooses to keep going
    /// after a rejected excuse isn't immediately re-nagged.
    static let continueAnywayGraceSeconds: TimeInterval = 120

    /// Length of the opt-in "timed break" offered on a confirmed drift.
    static let breakSeconds: TimeInterval = 5 * 60
}
