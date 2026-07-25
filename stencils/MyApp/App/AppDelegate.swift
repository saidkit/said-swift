import AppKit

/// Composes; does not implement (ADR-SWIFT-S01 rule 1).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build your AppEnvironment here and hand off to a feature (ADR-SWIFT-S05).
    }
}
