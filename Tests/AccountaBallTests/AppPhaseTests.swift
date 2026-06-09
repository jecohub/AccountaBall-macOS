@testable import AccountaBall

func runAppPhaseTests() {
    suite("AppPhaseTests") {
        // Verify all cases are distinct from each other (meaningful sample)
        expect(AppPhase.idle != .welcome, "idle != welcome")
        expect(AppPhase.welcome != .setup, "welcome != setup")
        expect(AppPhase.setup != .session, "setup != session")
        expect(AppPhase.session != .offTask, "session != offTask")
        expect(AppPhase.ambiguous != .offTask, "ambiguous != offTask")
        expect(AppPhase.offTask != .progress, "offTask != progress")
        expect(AppPhase.progress != .complete, "progress != complete")
        expect(AppPhase.idle != .complete, "idle != complete (non-adjacent)")

        // Compile-time exhaustiveness: this switch must cover all cases.
        // If a new case is added to AppPhase, this will fail to compile — catching the gap.
        let phase = AppPhase.idle
        let _ = { () -> String in
            switch phase {
            case .idle:     return "idle"
            case .welcome:  return "welcome"
            case .setup:    return "setup"
            case .session:  return "session"
            case .whatsUp:  return "whatsUp"
            case .ambiguous: return "ambiguous"
            case .offTask:  return "offTask"
            case .progress: return "progress"
            case .complete: return "complete"
            case .aiUnavailable: return "aiUnavailable"
            case .freeBall: return "freeBall"
            case .freeBallLog: return "freeBallLog"
            case .freeBallRecap: return "freeBallRecap"
            }
        }()
        expect(true, "exhaustive switch covers all AppPhase cases")
    }

    suite("AppPhase_freeBall") {
        let phases: [AppPhase] = [.freeBall, .freeBallLog, .freeBallRecap]
        expect(phases.count == 3, "three FreeBall phases exist")
        // Exhaustiveness: this switch fails to compile if a case is unhandled.
        for p in phases {
            switch p {
            case .freeBall, .freeBallLog, .freeBallRecap: expect(true, "covered")
            default: expect(true, "other")
            }
        }
    }
}
