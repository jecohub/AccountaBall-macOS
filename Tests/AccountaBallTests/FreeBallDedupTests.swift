@testable import AccountaBall

func runFreeBallDedupTests() {
    suite("FreeBallDedup") {
        // A realistic editor screen: a clock tick is a trivial 2-token change
        // against the screen's many tokens, so it must read as the same screen.
        let a = "Editing AppDelegate.swift func applicationDidFinishLaunching window "
              + "makeKeyAndOrderFront panel contentView NSHostingView rootView "
              + "RootCoordinatorView environmentObject state captureService ocrService"
        let aClock = a + " 10:42"   // trivial change (clock tick)
        expect(FreeBallDedup.isSameScreen(a, aClock, threshold: 0.85), "near-identical = same screen")

        let b = "Watching a YouTube video about basketball highlights"
        expect(!FreeBallDedup.isSameScreen(a, b, threshold: 0.85), "different content = new screen")

        expect(FreeBallDedup.similarity("foo bar baz", "foo bar baz") == 1.0, "identical = 1.0")
        expect(FreeBallDedup.similarity("foo bar", "nothing here") < 0.2, "disjoint ~ 0")
    }
}
