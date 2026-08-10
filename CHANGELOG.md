# Changelog

This file records user-visible changes. The project currently publishes source releases; signed binary distribution remains a follow-up.

## Unreleased

### Added

- Public open-source documentation in English.
- Contributor, security, CI, and issue-reporting guidance.
- macOS test/build workflow for pushes and pull requests.
- Native area capture and local image annotation with drawing, line, arrow, and rectangle tools.
- Direct `Edit image` actions for image items in the history picker.
- Local screen recording to animated GIF, copied directly to the pasteboard and history.
- Native local GIF export from the menu bar and individual GIF history rows.
- Search-as-you-type across text, content kind, and file metadata.
- Individual item deletion, clear-unpinned history, and one-shot `Ignore Next Copy` privacy action.
- Local picker shortcuts `⌘1`–`⌘9` for direct paste of visible results.
- Opt-in Launch at Login using Apple's `SMAppService` API.
- Privacy controls for ignored applications, temporary capture pauses, and age-based retention of unpinned history.
- Clipboard Stack capture and sequential paste controls for ordered form and data entry.
- Optional, unset-by-default hotkeys for starting a Clipboard Stack and pasting its next item.
- Native Quick Look previews for copied text, images, animated GIFs, and local file references.
- Local, asynchronous OCR indexing for copied static images and screenshots.
- On-demand `Extract Text & Copy` for static image history items, using the existing local Vision OCR result and adding the extracted plain text to history.
- Persistent text Favorites/Snippets with search, editable titles/content, paste, and deletion.
- A permanent local Library for text snippets, with optional collections, tags, metadata search, and filters.
- Authenticated AES-GCM encryption for History and Library files with a device-only Keychain-managed key.
- Optional Touch ID or Mac-password authentication before opening History or the Library.
- Source application metadata for new captures, with compact local filters by type, date, source app, pinned state, and OCR availability.

### Current feature set

- Menu-bar clipboard history for text, rich text, images, and file references.
- Configurable global hotkeys: history defaults to `⌘⇧V`, GIF recording defaults to `⌘G` and toggles recording.
- Local persistence, SHA-256 deduplication, configurable 10–200 item limit, and up to three pinned items.
- Compact keyboard-friendly picker with scrolling, smooth entrance animation, dismissal controls, and Liquid Glass on macOS 26.
- Accessibility-aware caret positioning and automatic paste with manual fallback.
- GIF capture with direct clipboard/history placement and manual stop/cancel controls.
- GIF export uses the native save panel and never duplicates the history item.
- Quick Look previews use temporary app-owned copies for image/text payloads and never alter original files.
- OCR text is persisted as local search metadata and never leaves the Mac.
- Source application metadata is persisted locally and remains optional for backward compatibility with older history files.
- OCR extraction copies plain text locally and does not upload image data or recognized text.
- Library items are persisted separately from history and are not removed by history retention or clearing.

### Known limitations

- Source builds are unsigned and not notarized.
- Apps that expose only a window-level accessibility element cannot provide an exact caret coordinate; the picker uses a deterministic area fallback.
- No cloud sync, signing, notarization, or App Store package is included.

### Repository and distribution

- Added a public `v1.1 — Core usability` GitHub milestone with acceptance-tested issues.
- Enabled GitHub Discussions for questions and product feedback.
- Added a release checklist covering signed/notarized DMG and Homebrew Cask preparation.
- Added a privacy-safe animated README preview generated from the app icon and synthetic clipboard content.
- Published source release `v1.0.0`; signed and notarized binary distribution remains pending.
