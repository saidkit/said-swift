# Technical Architecture

Replace this file with your project's architecture. The structure below is what the
said-swift spine assumes; fill in the product-specific parts.

## System Design

<PROJECT> is a macOS app: an AppKit shell hosting SwiftUI content, with feature modules
behind a composition root and system frameworks behind service contracts.

## Technology Stack

- **Language**: Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`
- **App shell**: AppKit — `NSApplication`, windows, `NSStatusItem`, menus, event monitors
- **View content**: SwiftUI hosted via `NSHostingView` / `NSHostingController`
- **State**: `@Observable` (`@MainActor`) — check the deployment-target note in `conventions.md`
- **Persistence**: `UserDefaults` behind a typed facade + files (ADR-SWIFT-S08)
- **Build**: Xcode, settings in `.xcconfig`, `make` facade over scripts
- **Distribution**: <Developer ID signed, hardened runtime, notarized and stapled | App Store | internal>

## Layers

- **`<Product>/App/`** — composition root: `AppDelegate` builds `AppEnvironment`, hands off
- **`<Product>/Features/<Name>/`** — capability modules, split along the `@MainActor` boundary
- **`<Product>/Core/<Service>/`** — one protocol + `Live`/`Stub` per system framework or external system
- **`<Product>/UI/`** — shared cross-feature views and design tokens

## Core Principles

- **`AppDelegate` composes; features implement** — ADR-SWIFT-S01, ADR-SWIFT-S05
- **The `@MainActor` boundary is the architecture** — views and state on it, logic and services
  off it (ADR-SWIFT-S03, ADR-SWIFT-S07)
- **System frameworks behind contracts** — one import site per framework (ADR-SWIFT-S04)
- **Three stores, split by the text-editor test** — app settings in `UserDefaults`, hand-authored
  configuration in a user-visible directory, generated data in Application Support (ADR-SWIFT-S08)
- **Build settings are reviewable text** — `.xcconfig`, never the target editor (ADR-SWIFT-S06)

## Architecture Decisions

See [`docs/adr/README.md`](adr/README.md) — system ADRs (`ADR-SWIFT-S0x`, the portable
said-swift spine) and project ADRs (`ADR-SWIFT-00x`, yours).
