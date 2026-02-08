# CodexBar iOS Port Scaffold

This folder contains a practical iOS app + widget scaffold for CodexBar usage display.

## What is included

- `CodexBariOSApp` (SwiftUI app)
- `CodexBariOSWidgetExtension` (WidgetKit extension)
- Shared snapshot model module from this package: `CodexBariOSShared`
- `project.yml` for [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Quick start

1. Install XcodeGen:

```bash
brew install xcodegen
```

2. Generate the iOS Xcode project:

```bash
cd ios
xcodegen generate
open CodexBariOS.xcodeproj
```

3. In Xcode:
- Set your Team for app + widget targets.
- Update bundle IDs if needed.
- Keep the same App Group in both entitlements:
  - `group.com.steipete.codexbar`

4. Build and run on iOS 17+ (simulator or device).

## Data flow

The iOS app and widget read/write `widget-snapshot.json` via App Group container using:

- `iOSWidgetSnapshot`
- `iOSWidgetSnapshotStore`

The expected JSON schema matches CodexBar's widget snapshot format (`provider`, `primary`, `secondary`, token usage, etc.).

## Current behavior

- Real auth flow for GitHub Copilot:
  - start Device Flow in-app
  - authorize with GitHub in browser
  - complete token exchange in-app
  - fetch live Copilot usage and persist widget snapshot
- If no snapshot exists, app can load sample data.
- You can still paste/import snapshot JSON directly in the app.
- Widget renders the selected provider from snapshot data.

## Known gap

- Codex/Claude/Gemini native iOS auth flows are not implemented yet in this scaffold.
