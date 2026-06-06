import Foundation
@testable import AccountaBall

func runExcuseVerdictTests() {
    suite("ExcuseVerdictTests") {
        let j = ExcuseVerdict.parse("JUSTIFIED | 2 | watching React tutorials")
        expect(j.justified == true, "justified flag")
        expect(j.taskIndex == 2, "task index parsed")
        expect(j.rule == "watching React tutorials", "rule parsed")

        let n = ExcuseVerdict.parse("NOT_JUSTIFIED | |")
        expect(n.justified == false, "not justified")
        expect(n.taskIndex == nil, "no task index")
        expect(n.rule == "", "empty rule")

        // A rejection's reason must be RETAINED (it's the "why" we surface + record);
        // only the task attribution is dropped when not justified.
        let nr = ExcuseVerdict.parse("NOT_JUSTIFIED | | social media")
        expect(nr.justified == false, "rejected with reason: not justified")
        expect(nr.taskIndex == nil, "rejected with reason: no task index")
        expect(nr.rule == "social media", "rejected verdict keeps the reason")

        // "NOT_JUSTIFIED" contains "JUSTIFIED" — must not false-positive.
        expect(ExcuseVerdict.parse("not justified").justified == false, "substring guard")
        expect(ExcuseVerdict.parse("garbage").justified == false, "unknown defaults not justified")
        expect(ExcuseVerdict.parse("JUSTIFIED").taskIndex == nil, "missing index tolerated")
    }
}
