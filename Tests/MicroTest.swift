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
