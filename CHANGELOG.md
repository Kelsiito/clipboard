# Changelog

This file records user-visible changes. The project does not publish versioned binary releases yet.

## Unreleased

### Added

- Public open-source documentation in English.
- Contributor, security, CI, and issue-reporting guidance.
- macOS test/build workflow for pushes and pull requests.
- Native area capture and local image annotation with drawing, line, arrow, and rectangle tools.
- Direct `Edit image` actions for image items in the history picker.
- Local screen recording to animated GIF, copied directly to the pasteboard and history.

### Current feature set

- Menu-bar clipboard history for text, rich text, images, and file references.
- Configurable global hotkeys: history defaults to `⌘⇧V`, GIF recording defaults to `⌘G` and toggles recording.
- Local persistence, SHA-256 deduplication, configurable 10–200 item limit, and up to three pinned items.
- Compact keyboard-friendly picker with scrolling, smooth entrance animation, dismissal controls, and Liquid Glass on macOS 26.
- Accessibility-aware caret positioning and automatic paste with manual fallback.
- GIF capture with direct clipboard/history placement and manual stop/cancel controls.

### Known limitations

- Source builds are unsigned and not notarized.
- Apps that expose only a window-level accessibility element cannot provide an exact caret coordinate; the picker uses a deterministic area fallback.
- No cloud sync, search, launch-at-login, per-item deletion, or App Store package is included.
