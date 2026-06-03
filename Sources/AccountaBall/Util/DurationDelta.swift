import Foundation

struct DurationDelta {
    let fasterThanPrevious: Bool
    let deltaMinutes: Int

    static func compare(current: TimeInterval, previous: TimeInterval) -> DurationDelta {
        let deltaSec = abs(current - previous)
        return DurationDelta(fasterThanPrevious: current < previous,
                             deltaMinutes: Int((deltaSec / 60).rounded()))
    }
}
