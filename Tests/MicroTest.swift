import Foundation

var _failures = 0
var _total = 0

func expect(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    _total += 1
    if cond {
        print("  ✅  \(msg)")
    } else {
        _failures += 1
        let f = file.split(separator: "/").last.map(String.init) ?? file
        print("  ❌  FAIL: \(msg)  [\(f):\(line)]")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    body()
}

// Async suite: the body is awaited directly. The whole test run is driven by a
// single top-level `Task { @MainActor in ... }` + `RunLoop.main.run()` in the
// test runner's main.swift, so there is no manual semaphore/run-loop pumping
// here — that re-entrant pumping is exactly what used to deadlock the runner.
@MainActor
func suite(_ name: String, _ body: @MainActor () async -> Void) async {
    print("\n\(name)")
    await body()
}

func reportAndExit() -> Never {
    print("\n────────────────────────────────")
    if _failures == 0 {
        print("✓  All \(_total) tests passed")
        exit(0)
    } else {
        print("✗  \(_failures)/\(_total) tests failed")
        exit(1)
    }
}
