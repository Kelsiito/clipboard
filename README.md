# clipboard

[![CI](https://github.com/Kelsiito/clipboard/actions/workflows/macos.yml/badge.svg)](https://github.com/Kelsiito/clipboard/actions/workflows/macos.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`clipboard` is a small, local-first clipboard history app for macOS. It lives in the menu bar and opens a compact Windows+V-style picker with `⌘⇧V`.

The project is source-first and intentionally simple: SwiftUI + AppKit, Apple frameworks only, no cloud, analytics, accounts, backend, or external runtime dependencies.

> Status: public implementation. The repository builds locally. Tagged releases can provide ad hoc signed Apple Silicon builds, but the app is not Developer ID signed, notarized, or distributed through the Mac App Store.

## Features

- Menu-bar-only app; it does not add a normal Dock icon.
- Configurable global hotkey, defaulting to `⌘⇧V`.
- Persistent history for plain text, RTF data, PNG/TIFF/JPEG images, and copied file references.
- SHA-256 fingerprints to avoid duplicate history entries.
- 50 stored items by default, configurable from 10 to 200.
- Up to three pinned items, always shown first.
- Compact picker with three visible rows, scrolling for older items, arrow-key navigation, `Enter` to paste, and `Esc` to close.
- Click-outside, close-button, and paste-to-dismiss behavior.
- Smooth spring entrance animation.
- Native Liquid Glass surfaces on macOS 26, with a material fallback on macOS 14–25.
- Settings window for the hotkey, history limit, clearing app-owned history, and Accessibility status.
- File bookmarks/references are stored locally; original files are never copied, moved, or deleted by the app.

## Requirements

- macOS 14 or newer.
- Xcode with a macOS SDK capable of building the project.
- A Mac where Accessibility permission can be granted if automatic paste is desired.

The project uses Swift 5 mode and has no Swift Package Manager, CocoaPods, or other third-party dependencies.

## Install and run from source

```sh
git clone https://github.com/Kelsiito/clipboard.git
cd clipboard
open clipboard.xcodeproj
```

In Xcode:

1. Select the `clipboard` scheme and `My Mac` as the run destination.
2. Build and run.
3. Look for the clipboard icon in the menu bar. The app is an accessory/menu-bar app, so it is not expected to appear in the Dock.
4. Open `Settings…` from the menu-bar item to configure the hotkey and history limit.

The command-line equivalents are:

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
```

The local Debug build is unsigned and not notarized. macOS may show a trust warning when launching a build compiled on another Mac; build and run it from Xcode or approve it in System Settings as appropriate for your environment.

## Release archives

Maintainers can publish an Apple Silicon release archive by pushing a semantic version tag such as `v2.0.0`. The release workflow runs the tests, builds the app in Release configuration, applies an ad hoc signature, and uploads both a ZIP archive and its SHA-256 checksum to GitHub Releases.

Release archives are not notarized by Apple. macOS may show a trust warning when opening them. Users who prefer not to run an unnotarized binary should build the app from source in Xcode.

## Usage

1. Copy text, an image, or one or more files normally.
2. Press `⌘⇧V` to open the history picker.
3. Select an item with the mouse or arrow keys.
4. Press `Enter` or click an item to restore it to the pasteboard and paste it into the previously active app.

Use the pin button or an item's context menu to pin/unpin it. The picker shows up to three rows at once; scroll for older entries. The menu-bar menu contains `Settings…` and `Quit`.

### Accessibility and positioning

Accessibility is requested only when needed. It enables two things:

- reading the focused text role and caret/selection bounds so the picker can open beside the active field;
- restoring the target app and sending `⌘V` for automatic paste.

If Accessibility is denied, the history picker still works and the selected item remains on the clipboard for a manual `⌘V`. Apps that do not expose a real editable text element use a deterministic window-area fallback instead of the mouse position. The Codex desktop app is one such case: macOS exposes its content as a full-window accessibility group, so `clipboard` anchors near the lower composer area rather than claiming an exact caret that it cannot read.

To grant access, open `Settings…` in `clipboard`, choose `Open System Settings`, then enable `clipboard` under **Privacy & Security → Accessibility**. The status in the settings window updates while the app is running.

## Privacy and local storage

Clipboard history can contain sensitive information. `clipboard` keeps it on the local Mac:

- History is stored at `~/Library/Application Support/clipboard/history.json`.
- The app creates its data directory with restrictive permissions and writes the history atomically.
- Text, rich-text data, and image payloads are stored locally in the history file.
- Copied files are represented by local security-scoped bookmarks/references; the original files are not copied into the history and are never deleted by clearing it.
- Concealed, transient, and autogenerated pasteboard entries are ignored.
- `Clear History` removes only data owned by `clipboard`; it does not empty the system pasteboard or delete source files.
- There is no sync, network service, account, telemetry, advertising, or analytics code in the app.

To remove all locally stored history, use `Clear History` in the settings window. To remove the app and its remaining support data manually, quit the app first and inspect the `~/Library/Application Support/clipboard/` directory before deleting it.

## Project structure

```text
clipboard.xcodeproj/             Native Xcode project
clipboard/                       App target
  clipboardApp.swift             Menu-bar scene and app lifecycle
  AppState.swift                 Hotkey, settings, paste orchestration
  PasteboardMonitor.swift        Pasteboard polling and filtering
  ClipboardStore.swift           Local persistence, dedupe, limits, pins
  Models.swift                   Codable history and hotkey models
  GlobalHotKey.swift             Carbon global hotkey registration
  ClipboardPanelController.swift Picker window, placement, and paste UI
  SettingsView.swift             Settings UI and Liquid Glass helpers
clipboardTests/                  XCTest coverage for core behavior
docs/                            Roadmap and implementation history
.github/workflows/               macOS test/build CI
```

## Development and validation

There are no generated dependencies to install. Make a focused change, run the unit tests and build, then manually check the affected macOS behavior.

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
git diff --check
```

The test suite covers persistence, image payloads, file bookmarks, deduplication, limits, pinning, empty/legacy data, hotkey defaults, and panel placement geometry. See [CONTRIBUTING.md](CONTRIBUTING.md) for the manual QA checklist and contribution rules.

## Known limitations

- Automatic paste and exact caret positioning depend on macOS Accessibility permission and on the target app exposing a standard editable text role.
- Electron/WebView apps may expose only a window or group; the fallback can target the composer area but cannot know an unavailable caret coordinate.
- File bookmarks can become stale if the original file is moved, deleted, or made inaccessible.
- The current project does not provide cloud sync, search, per-item deletion, launch-at-login, signing, notarization, or App Store packaging.
- Builds from source are currently unsigned and should be treated as development builds.

The planned follow-up work is tracked in [docs/roadmap.md](docs/roadmap.md).

## Contributing

Bug reports, focused fixes, documentation improvements, and UX feedback are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Do not attach real clipboard history, private text, screenshots containing sensitive data, or credentials to issues or pull requests.

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

The application UI and repository documentation are English.

## License

`clipboard` is released under the [MIT License](LICENSE).
