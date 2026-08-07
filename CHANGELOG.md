# Changelog

This file records user-visible changes. Tagged releases can include ad hoc signed Apple Silicon builds, but the project does not publish Developer ID signed or notarized binaries.

## Unreleased

### Added

- Public open-source documentation in English.
- Contributor, security, CI, and issue-reporting guidance.
- macOS test/build workflow for pushes and pull requests.
- Tag-driven workflow for ad hoc signed Apple Silicon release archives and checksums.

### Current feature set

- Menu-bar clipboard history for text, rich text, images, and file references.
- Configurable global hotkey with a default of `⌘⇧V`.
- Local persistence, SHA-256 deduplication, configurable 10–200 item limit, and up to three pinned items.
- Compact keyboard-friendly picker with scrolling, smooth entrance animation, dismissal controls, and Liquid Glass on macOS 26.
- Accessibility-aware caret positioning and automatic paste with manual fallback.

### Known limitations

- Source builds are unsigned and not notarized.
- Apps that expose only a window-level accessibility element cannot provide an exact caret coordinate; the picker uses a deterministic area fallback.
- No cloud sync, search, launch-at-login, per-item deletion, or App Store package is included.
