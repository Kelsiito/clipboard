# Contributing to clipboard

Thanks for your interest in `clipboard`. Small, focused pull requests are welcome, especially bug fixes, documentation improvements, accessibility fixes, and macOS UI polish.

## Before you start

- Read the [README](README.md) and [roadmap](docs/roadmap.md).
- Check existing issues and pull requests before opening a duplicate.
- Check the [v1.1 milestone](https://github.com/Kelsiito/clipboard/milestone/1) before proposing duplicate roadmap work.
- Use [Discussions](https://github.com/Kelsiito/clipboard/discussions) for questions, product feedback, and early design discussion.
- Do not include real clipboard history, private text, personal files, credentials, or sensitive screenshots in an issue or pull request.
- Keep the project local-first. Do not add cloud sync, telemetry, analytics, authentication, or third-party services without a separate design discussion.

## Development setup

Requirements:

- macOS 14 or newer.
- Xcode with a compatible macOS SDK.
- No external package manager or dependency installation is required.

```sh
git clone https://github.com/Kelsiito/clipboard.git
cd clipboard
open clipboard.xcodeproj
```

Use the `clipboard` scheme and `My Mac` destination in Xcode. The app is a menu-bar accessory and normally does not appear in the Dock.

## Validation

Run the focused checks before submitting a change:

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
git diff --check
```

For changes to the picker or settings, also run the relevant manual checks:

- copy and paste plain text;
- copy and paste an image;
- copy multiple files and verify their references;
- restart the app and verify history persistence;
- open the picker with the default and a changed history hotkey;
- start and stop GIF recording with the default and a changed GIF hotkey;
- configure, use, and clear the optional Clipboard Stack start and paste-next hotkeys;
- open Quick Look from the row eye button and context menu for text, images, animated GIFs, and local files;
- copy a synthetic screenshot, wait for local OCR indexing, and find it by searching text visible only inside the image;
- use `Extract Text & Copy` on a synthetic screenshot, verify the recognized plain text reaches the system clipboard and appears as a new text history item, and verify an image with no text does not create one;
- capture a non-sensitive test area, draw with each annotation tool, and copy the finished PNG;
- record a short non-sensitive area with the GIF selection overlay, stop it from the menu bar, and verify it is animated;
- verify the GIF appears in history and pastes with `⌘V`;
- save the latest GIF from the menu bar and an individual GIF from its history row, including a filename without an extension, and verify the exported file is a valid `.gif` without duplicating history;
- cancel a GIF recording and verify no history item or local file is created;
- save a text history item as a Favorite, create and edit a Favorite, paste it, search it, delete it, and verify it survives history cleanup and restart;
- verify search-as-you-type, filtered arrow navigation, `Enter`, `Esc`, and `⌘1`–`⌘9` shortcuts;
- delete one item from its context menu and verify it stays deleted after restart;
- clear unpinned history and verify pinned items remain;
- choose `Ignore Next Copy`, copy synthetic content, and verify only that copy is skipped;
- open Settings → Privacy, ignore a running test app, and verify copies from it are not stored;
- pause history for 15 minutes, resume it, and verify paused copies are not stored;
- choose a short retention period with synthetic old fixtures and verify unpinned items expire while pinned items remain;
- start a Clipboard Stack, copy synthetic fields in order, finish it, and paste each queued item into a test field;
- clear or cancel a stack and verify no extra history payload is created;
- close a Quick Look preview and verify it does not add history or modify the original file;
- verify OCR search metadata persists after restarting the app and that invalid/non-text images remain usable;
- enable and disable Launch at Login, then verify the setting survives relaunch;
- verify close button, click-outside dismissal, scrolling, and pinning;
- verify Settings, Clear History, Clear unpinned, Ignore Next Copy, Quit, and the menu-bar item;
- test with Accessibility denied and granted;
- test target positioning in a standard text editor and in an app that exposes only a window-level accessibility element.

Do not use real sensitive clipboard content for screenshots or automated fixtures. Use deterministic fake text, images, and file paths.

## Code guidelines

- Prefer Apple frameworks and the existing SwiftUI/AppKit architecture.
- Keep state local and explicit; avoid introducing dependencies for small features.
- Preserve the existing data format or add backward-compatible decoding when changing persisted models.
- Do not delete original files when changing file-history behavior.
- Keep Accessibility requests narrow and explain user-visible fallbacks.
- Add or update focused XCTest coverage for persistence, filtering, deduplication, limits, and geometry changes.
- Keep source identifiers, user-facing strings, and developer documentation in English.

## Pull requests

Use a concise title that describes the change. The description should include:

- what changed and why;
- the affected user behavior;
- tests/build commands and their results;
- manual QA performed or skipped;
- known limitations or follow-up work.

Keep unrelated formatting churn out of the pull request. A maintainer may ask for a smaller patch if a change mixes unrelated concerns.

For release or distribution changes, read [docs/release.md](docs/release.md). Do not commit signing identities, notarization credentials, certificates, provisioning material, or private test data.

## Commit messages

Use short, imperative commit messages with a clear scope, for example:

- `fix: keep picker above the focused composer`
- `docs: clarify local history storage`
- `test: cover legacy history decoding`

## License

By contributing, you agree that your contributions are provided under the [MIT License](LICENSE).
