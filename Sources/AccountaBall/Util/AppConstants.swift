import Foundation

/// App-wide constants shared across the engine and utilities so values that
/// must stay in lockstep can't drift apart.
enum AppConstants {
    /// The capture/classify cycle length. The capture loop fires on this
    /// interval, each on-task cycle credits this many seconds to the task's
    /// `timeOnTask`, and the timeline coalescer extends the last range by it.
    static let cycleSeconds: TimeInterval = 5
}
