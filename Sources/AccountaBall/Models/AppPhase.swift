enum AppPhase: Equatable {
    case idle
    case welcome
    case setup
    case session
    case whatsUp
    case ambiguous
    case offTask
    case progress
    case complete
    case aiUnavailable
    // FreeBall — passive observation mode (separate engine).
    case freeBall       // collapsed calm "observing" ball
    case freeBallLog    // live session log: timer + End Session
    case freeBallRecap  // post-session summary + breakdown
    case freeBallHistory  // past-sessions browser
}
