import Foundation
@testable import AccountaBall

func runDebugLogTests() {
    suite("DebugLogTests") {
        expect(DebugLog.truncate("hello", max: 10) == "hello", "short string unchanged")
        expect(DebugLog.truncate("hello world", max: 5) == "hello…", "truncated with ellipsis")
        expect(DebugLog.shouldRotate(sizeBytes: 1_000_000) == false, "under 5MB no rotate")
        expect(DebugLog.shouldRotate(sizeBytes: 6_000_000) == true, "over 5MB rotates")
    }
}
