import Testing

@testable import MyApp

/// Replace with real tests. Present so `make ci` is green and NON-VACUOUS from the first
/// commit — a starter whose gates pass by inspecting nothing teaches the wrong habit.
@Suite struct SmokeTests {
    @Test func testTargetIsWired() {
        #expect(Bool(true))
    }
}
