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
- Menu-bar-only lifecycle with configurable history (`⌘⇧V`) and GIF (`⌘G`) global hotkeys.
- Plain text, RTF, PNG/TIFF/JPEG images, and file bookmarks/references.
- Native area capture followed by a lightweight local annotation editor.
- Native area screen recording converted locally to animated GIF and copied to the pasteboard/history.
- The latest GIF or an individual GIF history item can be exported to a local `.gif` file.
- Persistent text Favorites/Snippets with search, editing, paste, and deletion.
- Local JSON persistence under `~/Library/Application Support/clipboard/`.
- SHA-256 deduplication, a configurable 10–200 item limit, and up to three pinned items.
- Compact picker with scrolling, keyboard navigation, close/outside-click dismissal, and smooth entrance animation.
- Accessibility-aware caret positioning and automatic paste with a manual `⌘V` fallback.
- Liquid Glass on macOS 26 with a material fallback on macOS 14–25.
- Unit tests, public documentation, MIT license, and macOS CI workflow.

## v1.1 — Core usability (implemented and merged)

This milestone is implemented in the current working tree. Each item remains independently reviewable through its GitHub issue:

- [Search-as-you-type](https://github.com/Kelsiito/clipboard/issues/3) — filter text and useful file metadata without changing persisted history.
- [Delete one history item](https://github.com/Kelsiito/clipboard/issues/4) — remove only the app-owned item payload.
- [Clear unpinned history](https://github.com/Kelsiito/clipboard/issues/5) — preserve pinned items and original files.
- [Ignore next copy](https://github.com/Kelsiito/clipboard/issues/6) — skip exactly one eligible pasteboard snapshot in memory.
- [Numbered picker shortcuts](https://github.com/Kelsiito/clipboard/issues/7) — keep `⌘1`–`⌘9` local to the focused picker.
- [Opt-in Launch at Login](https://github.com/Kelsiito/clipboard/issues/8) — use Apple's login-item API with an off-by-default setting.

Milestone: [v1.1 — Core usability](https://github.com/Kelsiito/clipboard/milestone/1).

## v1.2 — Privacy controls (implemented and merged)

The first v1.2 slice keeps capture local and gives users predictable ways to stop or limit it:

- Ignore selected running applications; copies from those apps are not stored.
- Pause capture for 15 minutes, 1 hour, or until manually resumed.
- Automatically remove unpinned items older than 1, 7, or 30 days.
- Preserve pinned items and original files during retention cleanup.

The pause state is intentionally session-only and resets when the app restarts. Ignored application identifiers and retention settings persist locally in UserDefaults.

## v1.3 — Power (implemented locally)

The first v1.3 slice is Clipboard Stack / sequential paste:

- Start a session-only stack from the menu bar.
- Capture subsequent eligible copies in their original order while keeping normal history capture active.
- Finish the stack and paste one queued item at a time into the focused destination.
- Keep the manual `⌘V` fallback when Accessibility is unavailable.
- Open native Quick Look previews for copied text, images, animated GIFs, and existing local file references.
- Index text from copied static images locally with Apple Vision so screenshots can be searched.
- Extract recognized text from a static image, copy it as plain text, and add the result to history.
- Export the latest GIF or an individual GIF history item to a local `.gif` file.
- Save text history items as persistent, editable Favorites/Snippets.

## Distribution and documentation track

These tasks are independent from feature implementation and do not block v1.1 coding:

- [Signed/notarized DMG and Homebrew Cask](https://github.com/Kelsiito/clipboard/issues/9) — blocked until a Developer ID identity and notarization credentials are available.
- [Sanitized README demo media](https://github.com/Kelsiito/clipboard/issues/10) — use synthetic content only; no private desktop screenshots.
- [GitHub Discussions](https://github.com/Kelsiito/clipboard/discussions) — enabled for questions and early product feedback.

## Explicit non-goals

- Cloud sync or remote clipboard storage.
- Accounts, authentication, analytics, telemetry, advertising, or a backend.
- Copying file bytes into history or deleting original files.
- Signed/notarized distribution in the source-first v1 release.

## Next candidates

These follow the v1.3 Clipboard Stack slice and are intentionally not committed to a release date:

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
