import AppKit

// Entry point is main.swift, NOT @main on the delegate — see ADR-SWIFT-S01 rule 9.
// @main on an NSApplicationDelegate does not invoke applicationDidFinishLaunching.

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
