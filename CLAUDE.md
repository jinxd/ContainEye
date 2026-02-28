# CLAUDE.md

This file defines how Claude Code should work in this repository.

## Mission

ContainEye is a SwiftUI iOS/macOS app for remote server operations. It combines server monitoring, Docker/process visibility, SFTP file management, test automation, and an SSH terminal (xterm.js in `WKWebView`) with an agentic assistant workflow.

Primary goal per change: ship reliable server tooling with clean SwiftUI architecture and strict concurrency-safe code.

## Current Scope (Source of Truth)

This repository currently contains:
- Main app: `ContainEye/`
- Widget extension: `TestsWidget/`
- Unit tests: `ContainEyeTests/`
- UI tests: `ContainEyeUITests/`
- Xcode project and schemes: `ContainEye.xcodeproj/`

## Product Plan

### Core Product Areas
1. Server Operations
- Maintain server inventory and connection metadata.
- Show health/usage summaries and deeper detail screens.

2. Container and Process Operations
- List Docker containers and compose stacks.
- Show process data and container/process detail views.

3. SFTP Workspace
- Remote file browsing and operations via SSH/SFTP.
- File editing/preview support via SFTP-related views.

4. Terminal Workspace
- Interactive SSH terminal with xterm.js web assets.
- Terminal settings, snippets, and command suggestions.

5. Automated Test Workspace ("Code" tab)
- Define server tests, run them, inspect status history, and manage flows.
- Integrate with App Intents and Spotlight handoff where present.

6. Agentic Workspace
- Route current screen context into agentic workflows.
- Keep context synced with navigation and selected resources.

7. Widget + Notifications
- Widget timelines reflect current testing/server state.
- Push registration and background refresh/test execution paths.

### UX Surface (from app entry)
Root navigation is `NavigationStack` + `TabView` in `ContainEye/Shared/ContentView.swift` with tabs for:
- `SFTP`
- `Terminal`
- `Servers`
- `Code`
- `Agentic`

Setup flow is shown when onboarding state requires it.

## Architecture Plan

### Module Map
- `ContainEye/App/`: app lifecycle, app delegate, background hooks.
- `ContainEye/Data/`: models, errors, SSH actor, persistence helpers, defaults.
- `ContainEye/Shared/`: cross-feature infrastructure, setup flow, dependencies, reusable views.
- `ContainEye/Server/`: server/container/process and compose UI.
- `ContainEye/SFTP/`: remote file system UX.
- `ContainEye/TerminalTab/`: terminal runtime, bridge/events, snippets, suggestions, web assets.
- `ContainEye/Tests/`: test management flows and detail screens.
- `ContainEye/AppIntents/`: shortcuts/intents integration.
- `ContainEye/URLs/`: URL/web wrappers.
- `TestsWidget/`: widget extension.

### Data and State
- Persistence: Blackbird SQLite (`SharedDatabase`).
- Security: credentials in Keychain, not in app DB models.
- Concurrency: async/await + actors (notably SSH client actor).
- Shared/global app context should be environment-driven and observable, not singleton-heavy.

### Third-Party Dependencies (from `Package.resolved`)
- Blackbird
- Citadel
- SwiftSH
- KeychainAccess
- ButtonKit
- TelemetryDeck SwiftSDK
- Supporting Swift packages (NIO, Crypto, Collections, etc.) pulled transitively/by feature

## Build and Test Commands

Use project-root commands:

```bash
# Build app for iOS Simulator
xcodebuild -scheme ContainEye -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run app test target on iOS Simulator
xcodebuild -scheme ContainEye -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Build widget extension scheme
xcodebuild -scheme TestsWidgetExtension -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Discover available simulators
xcrun simctl list devices available
```

If a named simulator is unavailable, switch destination to any available iOS simulator from `simctl` output.

## Engineering Instructions (Mandatory)

### SwiftUI Design Rules
- Use as little explicit spacing/padding/font-weight tweaking as possible.
- Prefer container-level modifiers (`VStack`/`Group`/wrapper) over repeating the same modifier on each child.
- Prefer `.accent` styling over hard-coded fixed colors when appropriate.
- Never nest two `NavigationStack`s.
- Never use `NavigationView`; use `NavigationStack` or `NavigationSplitView`.
- Only when using `NavigationSplitView`: a nested `NavigationStack` is allowed in the **detail** pane only.
- In each sheet add a new NavigationStack and .confirmable() outside the views that actually use it.
- Never add padding around List, Form or NavigationStack.
- Try to stick to built-in styles and components.
- For Buttons executing async actions use AsyncButton.
- For all close, cancel or confirming toolbar buttons use button roles and do not add a symbol or title.

### State and Dependency Rules
- Pass as little state as possible into child views.
- For state shared across many views, use environment injection with an `@Observable` type.
- Avoid singletons unless one process-wide instance is genuinely required.

### View Composition and File Organization
- Do not place multiple computed subviews inside one view struct.
- Keep distinct view structs in separate files.
- Organize view files in folders by feature purpose and usage location.
- Keep files focused; split when one file starts handling unrelated responsibilities.

### Coding Quality Rules
- Keep strict Swift concurrency correctness in mind for every change.
- Prefer explicit, typed models over ad-hoc dictionaries.
- Keep side effects near boundary layers (network, storage, app lifecycle).
- Do not add dead code, placeholder TODO blocks, or speculative abstractions.

## Task Execution Playbook (What Claude Should Do)

For every coding task:
1. Identify impacted feature area(s) and exact files.
2. Apply a coherent change that results in the least amount of code necessary, but meets expectations. 
3. Preserve architecture rules above (navigation/state/file boundaries).
4. Build or test the touched surface whenever possible.
5. Update docs (`CLAUDE.md`) if scope/commands/architecture changed.
6. Summarize: changed files, behavioral effect, and what was validated.

When refactoring UI:
1. First remove duplicated child-level modifiers by lifting to parent containers.
2. Reduce explicit spacing/padding/font-weight overrides unless required.
3. Verify navigation structure still follows `NavigationStack`/`NavigationSplitView` rules.
4. Verify shared state is environment-driven where cross-feature usage exists.

## Auto-Update Policy For This File

`CLAUDE.md` must be updated in the same task/PR when any of these change:
- App module/folder structure.
- User-facing feature surfaces (tabs, major screens, or flows).
- Build/test commands or schemes.
- Core dependencies or deployment/toolchain targets.
- Architectural rules or team coding constraints.

### Update Procedure
1. Inspect changed files (`git diff --name-only`).
2. If any trigger above matches, edit `CLAUDE.md` before finishing.
3. Keep content factual and aligned to current repo state.
4. Remove stale sections instead of appending contradictory text.
5. Keep `AGENTS.md` pointing to `CLAUDE.md`.

## Practical Guardrails

- Prefer editing existing files over creating new abstractions unless needed.
- Do not change deployment targets or package versions unless task requires it.
- Do not introduce a second navigation root architecture for the same flow.
- Do not bypass environment-based dependency wiring with hidden globals.

## Quick Project Snapshot

- App target uses SwiftUI with modern Apple-platform APIs.
- iOS deployment target in project file is `26.0`.
- Widget extension is part of the same workspace and should stay compatible with shared data/state boundaries.

Keep this file precise and current. If code reality changes, update this document immediately.
