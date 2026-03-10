# Vibe Food Agent Notes

## Project Overview

- App: `Vibe Food`
- Platform: iOS
- UI: SwiftUI
- State: feature-local `@Observable` stores
- Persistence: SwiftData
- Bundle ID: `ninja.roz.vibefood`
- Deployment target: iOS `26.2`
- Main Xcode project: `Vibe Food/Vibe Food.xcodeproj`
- Main source root: `Vibe Food/Vibe Food`
- Runtime dependency policy: no third-party runtime dependencies are currently used

## Architecture

- Composition root: `Vibe Food/Vibe Food/App/AppContainer.swift`
- SwiftData models: `Vibe Food/Vibe Food/Item.swift`
- Shared value types and enums: `Vibe Food/Vibe Food/Domain/Types.swift`
- Domain services: `Vibe Food/Vibe Food/Domain/Services.swift`
- Repositories and persistence implementations: `Vibe Food/Vibe Food/Persistence/Repositories.swift`
- Reset flow: `Vibe Food/Vibe Food/Persistence/ResetService.swift`
- Shared day navigation state: `Vibe Food/Vibe Food/Features/Shared/DaySelectionStore.swift`
- Shared visual system: `Vibe Food/Vibe Food/Features/Shared/AppGlass.swift`

## Product Shape

- Local-first nutrition tracker with no account requirement
- Tabs: `Dashboard`, `Food`, `Input`, `Water`, `Settings`
- AI is assistive only: it produces drafts first and must not auto-save records directly

## Important Invariants

- Preserve `localDayKey` semantics for day-based behavior
- Meals must keep ingredient snapshots so historical meals do not change when ingredients are edited later
- Ingredient and meal deletes are soft deletes
- `SettingsRecord.id` must remain `"settings"`
- `AIIntegrationRecord.id` must remain `"ai-integration"`
- Reset must clear insights too, then reseed default singleton records

## Build And Verification

- Use full Xcode, not Command Line Tools only
- Expected developer directory: `/Applications/Xcode.app/Contents/Developer`
- Preferred build output path for terminal verification: `.deriveddata`
- Simulator verification is part of build verification
- Always run `make rebuild` after making changes so updates are installed and visible in the simulator
- Use `make debug` when real-time log streaming is needed during diagnosis
- Preferred command interface: root `Makefile`

### Default Simulator

- Device: `iPhone 17 Pro`
- Runtime: iOS `26.2`
- UDID: `4960D9F5-2D8E-4980-B843-A4BCC70B47CD`
- Do not operate the simulator UI directly without explicit user permission
- Before clicking, dragging, navigating tabs, typing, or changing in-app state, ask the user first
- Build, install, launch, boot, and screenshot commands are fine without asking, but UI interaction is not

### Preferred Commands

- `make build`
  - Build-only (use when install/launch is not needed)
- `make run`
  - Boot the default simulator, install the current build, and launch the app
- `make debug`
  - Build, run, and stream live app logs for `ninja.roz.vibefood`
- `make rebuild`
  - Mandatory post-change verification flow: run `build` and then `run`
- `make boot`
  - Boot the default simulator and wait until it is ready
- `make install`
  - Install the current built app into the default simulator
- `make launch`
  - Launch the app in the default simulator
- `make screenshot`
  - Save a simulator screenshot to `/tmp/vibe-food` and print the file path
- `make clean`
  - Remove `.deriveddata`

### Underlying Commands

- Build:
  - `xcodebuild -project 'Vibe Food/Vibe Food.xcodeproj' -scheme 'Vibe Food' -configuration Debug -destination 'platform=iOS Simulator,id=4960D9F5-2D8E-4980-B843-A4BCC70B47CD' -derivedDataPath '.deriveddata' build`
- Boot simulator:
  - `open -a Simulator --args -CurrentDeviceUDID 4960D9F5-2D8E-4980-B843-A4BCC70B47CD`
  - `xcrun simctl boot 4960D9F5-2D8E-4980-B843-A4BCC70B47CD`
  - `xcrun simctl bootstatus 4960D9F5-2D8E-4980-B843-A4BCC70B47CD -b`
- Install:
  - `xcrun simctl install 4960D9F5-2D8E-4980-B843-A4BCC70B47CD '.deriveddata/Build/Products/Debug-iphonesimulator/Vibe Food.app'`
- Launch:
  - `xcrun simctl launch 4960D9F5-2D8E-4980-B843-A4BCC70B47CD ninja.roz.vibefood`
- Debug stream:
  - `xcrun simctl spawn 4960D9F5-2D8E-4980-B843-A4BCC70B47CD log stream --style compact --level info --predicate 'subsystem == "ninja.roz.vibefood"'`

## Repo-Specific Gotchas

- The Xcode project uses filesystem-synchronized groups, so adding or moving files is simpler than in older hand-managed `.pbxproj` setups
- Files placed under the app source root can end up bundled as app resources; current build output shows docs such as `README.md`, `PLAN.md`, and `LLM_CONTEXT.md` being copied into the app bundle
- If you add documentation or large non-runtime files, avoid placing them inside `Vibe Food/Vibe Food` unless bundling them is intentional
- When verifying app changes from the terminal, prefer `make rebuild` so the current build is also installed and launched on the pinned simulator
- Use `make debug` instead of `make rebuild` when you need live logs while the app is running
