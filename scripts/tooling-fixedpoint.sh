#!/bin/bash
# Asserts that swift-format and SwiftLint AGREE — that formatting is a fixed point.
#
# The failure this catches: swift-format rewrites a construct into a shape SwiftLint
# rejects. Neither tool yields, so `make format && make lint` can never both pass, and
# the person who hits it wastes an afternoon before disabling a gate. Verified cases:
# trailing commas in multiline literals (formatter adds, linter forbade) and long string
# literals (formatter cannot break, linter flagged length).
#
# Run after changing .swiftlint.yml or .swift-format, or after bumping either tool.
# ADR-SWIFT-S10 rule 4.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src"

# Constructs the conventions doc tells people to write, plus the shapes a formatter and a
# linter are most likely to disagree about.
cat > "$WORK/src/FixedPoint.swift" <<'SWIFT'
import Foundation
import OSLog

enum SampleError: Error {
    case notFound(URL)
    case unreadable(URL, underlying: Error)
}

protocol SampleWatcher: Sendable {
    func events(for url: URL) -> AsyncStream<SampleEvent>
}

struct SampleEvent: Sendable {
    let url: URL
    let kind: Kind
    enum Kind: Sendable { case created, modified, removed }
}

actor LiveSampleWatcher: SampleWatcher {
    nonisolated func events(for url: URL) -> AsyncStream<SampleEvent> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

@MainActor
final class SampleState {
    private(set) var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

nonisolated struct SampleFormatter: Sendable {
    func format(_ event: SampleEvent) -> String {
        switch event.kind {
        case .created: return "created"
        case .modified: return "modified"
        case .removed: return "removed"
        }
    }
}

@MainActor
struct SampleFeature {
    struct Deps: Sendable {
        var evaluate: @Sendable (String) async throws -> String
        var report: @Sendable (SampleError) -> Void
    }
}

enum Adversarial {
    // A formatter cannot break a string literal — the line stays long by necessity.
    static let message =
        "A deliberately very long single string literal that no formatter is able to break apart automatically at all."

    // Multiline literals: where trailing-comma style disagreements surface.
    static let table: [String: Int] = [
        "alpha": 1,
        "beta": 2,
    ]

    static let numbers = [
        1, 2, 3,
        4, 5, 6,
    ]

    static let closure: (Int) -> Int = { value in value * 2 }
}

enum SampleLog {
    static let sample = Logger(subsystem: "com.example.sample", category: "sample")
}
SWIFT

FMT_CFG="$ROOT/.swift-format"
cp "$ROOT/.swiftlint.yml" "$WORK/.swiftlint.yml"
# Point the linter at the scratch tree regardless of the project's own `included:` path.
/usr/bin/sed -i '' -E "s|^included:|included:\n  - src|" "$WORK/.swiftlint.yml"

echo "1/3  formatting…"
xcrun swift-format format --in-place --recursive --configuration "$FMT_CFG" "$WORK/src"

echo "2/3  checking the formatter is idempotent…"
cp "$WORK/src/FixedPoint.swift" "$WORK/pass1.swift"
xcrun swift-format format --in-place --recursive --configuration "$FMT_CFG" "$WORK/src"
if ! diff -q "$WORK/pass1.swift" "$WORK/src/FixedPoint.swift" >/dev/null; then
    echo "FAIL: swift-format is not idempotent with this configuration — it oscillates."
    diff -u "$WORK/pass1.swift" "$WORK/src/FixedPoint.swift" || true
    exit 1
fi

echo "3/3  linting the formatter's own output…"
cd "$WORK"
if ! swiftlint lint --strict --config "$WORK/.swiftlint.yml" src; then
    echo
    echo "FAIL: SwiftLint rejects swift-format's output — the two tools disagree."
    echo "      Disable the offending SwiftLint rule (swift-format owns formatting) or"
    echo "      change .swift-format. Do not leave it: 'make format' then 'make lint'"
    echo "      can never both pass, and the gate will get bypassed."
    exit 1
fi

echo
echo "OK — formatting is a fixed point: swift-format's output passes SwiftLint --strict."
