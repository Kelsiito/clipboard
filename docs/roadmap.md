# Roadmap

## Project status

The public v1 implementation is complete and available in the [`Kelsiito/clipboard`](https://github.com/Kelsiito/clipboard) repository. The project is a local macOS utility, not a cloud product or App Store release.

## Product goals

- Capture useful clipboard content locally.
- Open history with a configurable global hotkey.
- Paste a selected item back into the previously active app.
- Keep the interface compact, keyboard-friendly, and menu-bar-only.
- Make privacy boundaries and permission fallbacks clear.

## Current v1 scope

- SwiftUI + AppKit macOS app targeting macOS 14+.
- Menu-bar-only lifecycle with a default `⌘⇧V` global hotkey.
- Plain text, RTF, PNG/TIFF/JPEG images, and file bookmarks/references.
- Native area capture followed by a lightweight local annotation editor.
- Local JSON persistence under `~/Library/Application Support/clipboard/`.
- SHA-256 deduplication, a configurable 10–200 item limit, and up to three pinned items.
- Compact picker with scrolling, keyboard navigation, close/outside-click dismissal, and smooth entrance animation.
- Accessibility-aware caret positioning and automatic paste with a manual `⌘V` fallback.
- Liquid Glass on macOS 26 with a material fallback on macOS 14–25.
- Unit tests, public documentation, MIT license, and macOS CI workflow.

## Explicit non-goals

- Cloud sync or remote clipboard storage.
- Accounts, authentication, analytics, telemetry, advertising, or a backend.
- Copying file bytes into history or deleting original files.
- App Store delivery, automatic login launch, or signed/notarized distribution in v1.

## Next candidates

These are intentionally not committed to a release date:

- Per-item deletion.
- Search and filtering for larger histories.
- Launch-at-login as an opt-in setting.
- Signed and notarized distribution.
- Optional App Store packaging, subject to the required sandbox and permission model.
- Additional accessibility and target-app compatibility improvements.

## Technical constraints and risks

- Automatic paste and exact caret positioning require macOS Accessibility permission.
- Some Electron/WebView apps expose only a window-level accessibility group. The picker uses a deterministic composer/window-area fallback in that case; it cannot invent an unavailable caret coordinate.
- File bookmarks may become stale after a file is moved, deleted, or made inaccessible.
- Source builds are currently unsigned and may trigger macOS trust warnings.
- Clipboard history is sensitive local data and should be treated accordingly.

## Definition of done for future changes

- The user-facing behavior is documented in English.
- Persisted-data changes are backward-compatible or explicitly migrated.
- Focused XCTest coverage is added or updated.
- The project test and build commands pass.
- `git diff --check` passes.
- Manual macOS behavior is checked with fake, non-sensitive clipboard fixtures.
- Privacy, permission, and fallback behavior are documented.
