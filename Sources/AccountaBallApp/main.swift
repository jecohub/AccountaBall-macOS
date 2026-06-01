import AppKit
import AccountaBall

NSApplication.shared.setActivationPolicy(.accessory)
let delegate = AppDelegate()
NSApp.delegate = delegate
NSApp.run()
