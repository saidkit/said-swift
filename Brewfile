# Tooling for the quality gates (ADR-SWIFT-S10). `brew bundle` installs; `brew bundle check`
# verifies. Pinning lives here because neither SwiftLint nor swift-format has a config-level
# version field — an unpinned bump can silently stop enforcing a rule.
#
# swift-format is NOT listed: it ships with the Xcode toolchain (`xcrun swift-format`).
# Installing a second copy from brew is how you end up formatting with one version and
# linting with another.

brew "swiftlint"        # R-GATE-LINT

# Opt-in gates — install these before adding `scan` to the ci chain (R-GATE-SECRETS,
# R-GATE-DEADCODE). Left commented so `brew bundle check` passes on a fresh clone.
# brew "gitleaks"       # R-GATE-SECRETS
# brew "periphery"      # R-GATE-DEADCODE
# brew "xcbeautify"     # readable xcodebuild output in CI
