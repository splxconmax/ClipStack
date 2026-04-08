# ClipStack

ClipStack is a macOS 13+ menu bar clipboard manager built with SwiftUI + AppKit.

It runs as an agent app with no Dock icon, watches the clipboard in the background, stores a persistent local history in SQLite, and exposes clips through a popover UI with search, filters, pinning, grouping, and paste-on-click support. Paste-on-click does not work for now.

## Features

- Menu bar only app with native `NSStatusItem` + `NSPopover` behavior
- Persistent clipboard history stored locally in SQLite
- Search across clip text, source app, and date tokens
- Support for text, rich text, URLs, images, file references, and code-style previews
- Pinned clips with rename and drag reorder
- Smart grouping for repeated copies from the same app
- Global shortcut support
- Paste-on-click with Accessibility permission prompt when needed. DOES NOT WORK FOR NOW
- Excluded apps list
- Local-only storage with no network services

## Project Layout

- `Package.swift`: Swift package manifest
- `Sources/ClipStackApp`: executable entrypoint
- `Sources/ClipStackCore`: app model, services, persistence, and UI
- `Sources/ClipStackChecks`: automated verification executable
- `Scripts/build_app.sh`: builds and packages `dist/ClipStack.app`
- `Scripts/test.sh`: runs the verification executable

## Build

Run:

```zsh
zsh Scripts/build_app.sh
```

This creates:

```text
dist/ClipStack.app
```

The build script prefers a release build and falls back to debug automatically if the local toolchain fails in optimized mode.

## Run

To launch the app from Finder:

- Open `dist/ClipStack.app`

To launch from Terminal:

```zsh
open dist/ClipStack.app
```

On first launch, ClipStack creates its local storage under:

```text
~/Library/Application Support/ClipStack
```

## Verify

Run:

```zsh
zsh Scripts/test.sh
```

This executes the `ClipStackChecks` verification target, which covers:

- search token behavior
- grouping behavior
- settings persistence
- history pruning with pinned retention
- stored asset cleanup
- pinned clip limit enforcement

## Notes

- The generated app bundle is currently unsigned.
- The bundle produced in this environment is arm64.
- Launch at Login may not work reliably until the app is distributed as a signed install.
- Paste-on-click needs Accessibility permission to synthesize `Cmd+V`. DOES NOT WORK FOR NOW

## Current Deliverable

The repo currently produces a working local `.app` bundle and includes the core menu bar app, persistence layer, build packaging, and automated verification runner.
