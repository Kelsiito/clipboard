# Contributing to clipboard

Thanks for your interest in `clipboard`. Small, focused pull requests are welcome, especially bug fixes, documentation improvements, accessibility fixes, and macOS UI polish.

## Before you start

- Read the [README](README.md) and [roadmap](docs/roadmap.md).
- Check existing issues and pull requests before opening a duplicate.
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
- open the picker with the default and a changed hotkey;
- verify arrow navigation, `Enter`, `Esc`, close button, click-outside dismissal, scrolling, and pinning;
- verify Settings, Clear History, Quit, and the menu-bar item;
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
- Keep source identifiers and developer documentation in English. The current app UI is PT-PT by design.

## Pull requests

Use a concise title that describes the change. The description should include:

- what changed and why;
- the affected user behavior;
- tests/build commands and their results;
- manual QA performed or skipped;
- known limitations or follow-up work.

Keep unrelated formatting churn out of the pull request. A maintainer may ask for a smaller patch if a change mixes unrelated concerns.

## Commit messages

Use short, imperative commit messages with a clear scope, for example:

- `fix: keep picker above the focused composer`
- `docs: clarify local history storage`
- `test: cover legacy history decoding`

## License

By contributing, you agree that your contributions are provided under the [MIT License](LICENSE).
