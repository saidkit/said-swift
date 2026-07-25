# said-swift — command facade (ADR-SWIFT-S06, tiering per ADR-SWIFT-S10)
#
# `make` is the stable verb for humans, CI, and agents. Gate targets carry the R-GATE-*
# rule they answer to; rule definitions live in docs/qa/feature-qa-checklist.md.
# Never inline a raw xcodebuild invocation into a doc, a task entry, or CI — put it here.
#
# TIERS (ADR-SWIFT-S10) — named for WHEN they run:
#   make pre-commit   seconds   format-check + lint       → .git pre-commit hook
#   make ci           minutes   + build + test            → .git pre-push hook, CI
#   make validate     release   signature + hardening     → on the built bundle
# `make install-hooks` wires the first two to git.

SHELL := /bin/bash

# ---- Project seam -----------------------------------------------------------
# These are the only lines a consuming project edits. Everything below is generic.
APP_NAME      ?= MyApp
APP_ROOT      ?= .
APP_SOURCES   ?= $(APP_ROOT)/$(APP_NAME)
WORKSPACE     ?= $(APP_ROOT)/$(APP_NAME).xcworkspace
SCHEME        ?= $(APP_NAME)
BUILD_DIR     ?= $(APP_ROOT)/build
ENTITLEMENTS  ?= $(APP_SOURCES)/Supporting/$(APP_NAME).entitlements

# Hardened-runtime exceptions this project has justified IN WRITING (ADR-SWIFT-S06).
# Empty by default: R-GATE-HARDENING fails on any exception not listed here. Add a key
# only alongside an ADR or task entry saying why. `get-task-allow` is never allowlistable.
HARDENING_ALLOW ?=
# -----------------------------------------------------------------------------

CONFIGURATION ?= Debug
BUNDLE        ?= $(BUILD_DIR)/$(APP_NAME).app
INFO_PLIST    ?= $(BUNDLE)/Contents/Info.plist
SWIFTLINT     ?= swiftlint
SWIFTFORMAT   ?= xcrun swift-format

DANGEROUS_ENTITLEMENTS := \
  com.apple.security.cs.disable-library-validation \
  com.apple.security.cs.allow-unsigned-executable-memory \
  com.apple.security.cs.allow-dyld-environment-variables \
  com.apple.security.cs.disable-executable-page-protection

.DEFAULT_GOAL := help
.PHONY: help doctor build clean test lint format format-check validate sign-check hardening \
        pre-commit ci scan scan-secrets scan-deadcode tooling-check install-hooks release \
        guard-workspace guard-bundle

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'

## doctor: report which gates can currently run
doctor:
	@echo "app sources : $(APP_SOURCES) $$([ -d "$(APP_SOURCES)" ] && echo present || echo MISSING)"
	@echo "workspace   : $(WORKSPACE) $$([ -d "$(WORKSPACE)" ] && echo present || echo MISSING)"
	@echo "entitlements: $(ENTITLEMENTS) $$([ -f "$(ENTITLEMENTS)" ] && echo present || echo MISSING)"
	@echo "swiftlint   : $$(command -v $(SWIFTLINT) >/dev/null && $(SWIFTLINT) version || echo 'MISSING — brew bundle')"
	@echo "swift-format: $$($(SWIFTFORMAT) --version 2>/dev/null || echo 'MISSING — ships with Xcode')"
	@echo "xcodebuild  : $$(xcodebuild -version 2>/dev/null | head -1 || echo MISSING)"
	@echo "gitleaks    : $$(command -v gitleaks >/dev/null && gitleaks version 2>/dev/null || echo 'not installed (opt-in, R-GATE-SECRETS)')"
	@echo "periphery   : $$(command -v periphery >/dev/null && periphery version 2>/dev/null || echo 'not installed (opt-in, R-GATE-DEADCODE)')"
	@printf "git hooks   : "; \
	  if [ "$$(git config --get core.hooksPath 2>/dev/null)" = "scripts/hooks" ]; then echo "installed"; \
	  else echo "NOT installed — run 'make install-hooks'"; fi
	@printf "lint scope  : "; \
	  swiftlint_inc=$$(awk '/^included:/{f=1;next} /^[a-z_]+:/{f=0} f && /^  - /{gsub(/^  - /,"");print;exit}' .swiftlint.yml); \
	  app_src="$(APP_SOURCES)"; app_src="$${app_src#./}"; \
	  if [ "$$swiftlint_inc" = "$$app_src" ]; then echo "OK ($$swiftlint_inc)"; \
	  else echo "MISMATCH — .swiftlint.yml included: '$$swiftlint_inc' vs APP_SOURCES '$$app_src'"; \
	       echo "              a stale included: path lints ZERO files and passes vacuously"; fi
	@echo "release     : NOT WIRED — see ADR-SWIFT-S06 for the required chain"

guard-workspace:
	@test -d "$(WORKSPACE)" || { \
	  echo "error: $(WORKSPACE) does not exist yet."; \
	  echo "       The app target has not been created — this gate cannot run."; \
	  echo "       Say so explicitly in the task's ### Fix rather than claiming a pass."; \
	  exit 1; }

guard-bundle:
	@test -d "$(BUNDLE)" || { echo "error: $(BUNDLE) not found — run 'make build' first."; exit 1; }

## build: compile the app — R-GATE-BUILD (Swift has no separate typecheck; the build is it)
build: guard-workspace
	xcodebuild -workspace "$(WORKSPACE)" -scheme "$(SCHEME)" \
	           -configuration $(CONFIGURATION) build

## test: run the unit-test suite — R-GATE-TEST
test: guard-workspace
	xcodebuild -workspace "$(WORKSPACE)" -scheme "$(SCHEME)" \
	           -configuration $(CONFIGURATION) test

## lint: SwiftLint, warnings as errors — R-GATE-LINT
lint:
	@if [ -d "$(APP_SOURCES)" ]; then \
	  $(SWIFTLINT) lint --strict --config .swiftlint.yml; \
	else echo "no Swift sources at $(APP_SOURCES) yet — R-GATE-LINT vacuous, say so in ### Fix"; fi

## format-check: verify formatting without writing — R-GATE-FORMAT
format-check:
	@if [ -d "$(APP_SOURCES)" ]; then \
	  $(SWIFTFORMAT) lint --strict --recursive --configuration .swift-format "$(APP_SOURCES)"; \
	else echo "no Swift sources at $(APP_SOURCES) yet — R-GATE-FORMAT vacuous, say so in ### Fix"; fi

## format: rewrite sources in place (what your editor should do on save)
format:
	@if [ -d "$(APP_SOURCES)" ]; then \
	  $(SWIFTFORMAT) format --in-place --recursive --configuration .swift-format "$(APP_SOURCES)"; \
	else echo "no Swift sources at $(APP_SOURCES) yet — nothing to format"; fi

## tooling-check: assert swift-format and SwiftLint agree — run after changing either config
tooling-check:
	@./scripts/tooling-fixedpoint.sh

## sign-check: signature / Gatekeeper / staple / entitlements — R-GATE-SIGN
sign-check: guard-bundle
	codesign --verify --deep --strict --verbose=2 "$(BUNDLE)"
	spctl --assess --type execute --verbose=4 "$(BUNDLE)"
	xcrun stapler validate "$(BUNDLE)"
	@# Entitlements are ASSERTED, not printed: a gate that only prints cannot fail.
	@test -f "$(ENTITLEMENTS)" || { \
	  echo "error: $(ENTITLEMENTS) not found — R-GATE-SIGN cannot assert entitlements"; exit 1; }
	@if diff -u <(xmllint --c14n --format "$(ENTITLEMENTS)" 2>/dev/null) \
	            <(codesign -d --entitlements :- "$(BUNDLE)" 2>/dev/null | xmllint --c14n --format -); \
	 then echo "  entitlements match $(ENTITLEMENTS)"; \
	 else echo "error: shipped entitlements differ from $(ENTITLEMENTS) (diff above)"; exit 1; fi

## hardening: get-task-allow / runtime flag / exceptions / ATS — R-GATE-HARDENING
hardening: guard-bundle
	@ents=$$(codesign -d --entitlements :- "$(BUNDLE)" 2>/dev/null || true); fail=0; \
	if echo "$$ents" | grep -q 'get-task-allow'; then \
	  echo "error: com.apple.security.get-task-allow is present in the shipped bundle."; \
	  echo "       Any process could attach a debugger and read its memory, and"; \
	  echo "       notarization will reject the build. Never allowlistable."; fail=1; \
	else echo "  get-task-allow absent"; fi; \
	for k in $(DANGEROUS_ENTITLEMENTS); do \
	  if echo "$$ents" | grep -q "$$k"; then \
	    case " $(HARDENING_ALLOW) " in \
	      *" $$k "*) echo "  allowed (justified via HARDENING_ALLOW): $$k" ;; \
	      *) echo "error: hardened-runtime exception '$$k' is not in HARDENING_ALLOW."; \
	         echo "       Remove it, or add it to the Makefile seam with a written justification."; fail=1 ;; \
	    esac; \
	  fi; \
	done; \
	if codesign --display --verbose=2 "$(BUNDLE)" 2>&1 | grep -q 'flags=.*runtime'; then \
	  echo "  hardened runtime enabled"; \
	else echo "error: hardened runtime is not enabled on the bundle"; fail=1; fi; \
	if [ -f "$(INFO_PLIST)" ] && \
	   /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoads' \
	     "$(INFO_PLIST)" 2>/dev/null | grep -qi true; then \
	  echo "error: NSAllowsArbitraryLoads is true — App Transport Security is disabled"; fail=1; fi; \
	if [ $$fail -ne 0 ]; then exit 1; else echo "  hardening OK"; fi

## validate: the release tier — R-GATE-SIGN + R-GATE-HARDENING
validate: sign-check hardening

## scan-secrets: R-GATE-SECRETS (opt-in — install gitleaks first)
scan-secrets:
	@command -v gitleaks >/dev/null || { \
	  echo "error: gitleaks not installed — R-GATE-SECRETS cannot run. Uncomment it in the Brewfile."; exit 1; }
	gitleaks detect --no-banner --redact

## scan-deadcode: R-GATE-DEADCODE (opt-in — install periphery first)
scan-deadcode: guard-workspace
	@command -v periphery >/dev/null || { \
	  echo "error: periphery not installed — R-GATE-DEADCODE cannot run. Uncomment it in the Brewfile."; exit 1; }
	periphery scan --workspace "$(WORKSPACE)" --schemes "$(SCHEME)" --targets "$(SCHEME)"

## scan: both opt-in scanners — add to the ci chain once the tools are installed
scan: scan-secrets scan-deadcode

## pre-commit: FAST tier (seconds) — format-check + lint. Wired to the git pre-commit hook.
pre-commit: format-check lint

## ci: FULL tier (minutes) — pre-commit + build + test. Wired to the git pre-push hook.
ci: pre-commit build test

## install-hooks: point git at scripts/hooks (pre-commit → fast, pre-push → full)
install-hooks:
	git config core.hooksPath scripts/hooks
	@echo "hooks installed: pre-commit → make pre-commit, pre-push → make ci"

## clean: remove build products
clean:
	rm -rf "$(BUILD_DIR)"

## release: NOT WIRED — the chain is specified in ADR-SWIFT-S06, not yet scripted
release:
	@echo "release is not wired yet. ADR-SWIFT-S06 specifies the required order:"
	@echo "  clean -> build -c Release -> validate -> notarytool submit --wait -> stapler staple -> archive"
	@echo "Implement it as a script under scripts/ and point this target at it."
	@exit 1
