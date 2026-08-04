# Project Summary

## Current Status

v1 implementation complete; Liquid Glass picker and caret-anchored Windows+V behavior ready for public repo.

## Latest Completed Task

- Date: 2026-08-04
- Task: Liquid Glass styling and active-field positioning fix
- Summary: Added native macOS 26 Liquid Glass surfaces, glass controls, and materialized picker entrance with a macOS 14–25 fallback. The picker now reads the system-wide focused Accessibility element and selected range before falling back to the focused app window; it no longer follows the mouse when a target app exists. Accessibility is prompted when the hotkey needs accurate anchoring or automatic paste.
- Validation: 10/10 unit tests passed; Debug test build passed; picker smoke showed Liquid Glass and placement above a TextEdit text area; settings smoke showed rendered Liquid Glass settings above another app.
- Git commit: pending.
- Git push status: pending.

- Date: 2026-08-04
- Task: Anchor picker to active text field
- Summary: Captured target app before activation, resolved focused AX text element and caret/selection, converted coordinates per screen, added a target-window fallback, and strengthened Windows+V-style spring/slide/fade animation.
- Validation: 10/10 unit tests passed; Debug build passed; picker screenshot showed it above active composer with safe gap; launch/hotkey smoke passed.
- Git commit: `deded00`.
- Git push status: public `Kelsiito/clipboard`; local/remote `main` SHA verified.

- Date: 2026-08-04
- Task: Fix blank settings window
- Summary: Rebuilt the custom settings window with an explicit `NSHostingController` frame, autoresizing, fixed content size, and minimum size so all settings sections render.
- Validation: 10/10 unit tests passed; Debug build passed; settings window screenshot showed Hotkey, Histórico, and Colagem automática; launch smoke passed.
- Git commit: `a07b211`.
- Git push status: public `Kelsiito/clipboard`; local/remote `main` SHA verified.

- Date: 2026-08-04
- Task: Compact picker UX and pinned history
- Summary: Added smooth hotkey animation, explicit close button, outside-deactivation dismissal, click-to-paste, three-row viewport with scroll, persistent pinning up to three items, Accessibility-aware positioning above focused text, and floating settings window.
- Validation: 10/10 unit tests passed; Debug build passed; compact picker screenshot verified; launch/hotkey smoke passed. Outside-click automation skipped because System Events lacked Accessibility permission.
- Git commit: `5b37eaf`.
- Git push status: public `Kelsiito/clipboard`; local/remote `main` SHA verified.

- Date: 2026-08-04
- Task: Implement clipboard macOS MVP
- Summary: Added pasteboard capture, persistent text/image/file history, global hotkey, picker panel, automatic paste flow, settings, tests, and App icon.
- Files changed: Project sources, tests, docs, icon assets.
- Commands run: Xcode/toolchain checks; icon generation and asset conversion; `xcodebuild test`; `xcodebuild build`; app launch smoke.
- Validation: 8/8 unit tests passed; Debug build passed; bundle launched and exited cleanly; icon catalog and `Info.plist` validated.
- Git commit: `2990e75` implementation; `b2d5111` publication record; `567ca9b` artifact ignore.
- Git push status: Public `origin/main` created; publication and housekeeping pushes verified.

## Task History

### 2026-08-04 — Anchor picker to active text field

**What was done**

- Passed captured target app into the picker instead of re-reading a possibly changed frontmost app.
- Used focused AX caret/selection bounds and per-screen coordinate conversion; mouse location is fallback when Accessibility cannot identify text input.
- Replaced subtle open transition with a spring pop-up that rises from the field area.

**Validation**

- Picker smoke screenshot showed panel above the active composer, with a non-overlapping gap.
- 10/10 tests, Debug build, and launch/hotkey smoke passed.

### 2026-08-04 — Fix blank settings window

**What was done**

- Fixed custom SwiftUI settings window content collapsing below the title bar.
- Added explicit hosting view frame/autoresizing and fixed/minimum window content size.
- Kept floating level, all-spaces behavior, and activation above other apps.

**Validation**

- Settings smoke screenshot showed all settings sections and controls.
- 10/10 unit tests passed.
- Debug build and launch smoke passed.

### 2026-08-04 — Compact picker UX and pinned history

**What was done**

- Added persistent `isPinned` state with backward-compatible decoding, pinned-first ordering, and a three-item cap.
- Added compact three-row picker, scrolling, pin controls/context menu, click-to-paste, close button, smooth open animation, dismissal on deactivation, and selected-text positioning when Accessibility is trusted.
- Replaced the standard settings scene action with a floating settings window that activates above other apps.

**Files changed**

- `clipboard/Models.swift`
- `clipboard/ClipboardStore.swift`
- `clipboard/AppState.swift`
- `clipboard/ClipboardPanelController.swift`
- `clipboard/clipboardApp.swift`
- `clipboardTests/ClipboardTests.swift`
- `README.md`, `docs/roadmap.md`, `docs/summary.md`

**Validation**

- 10/10 tests passed.
- Debug build passed.
- Picker opened from `⌘⇧V`, showed exactly three rows, and displayed close/pin controls.
- Launch and hotkey smoke passed without clipboard mutation.
- System Events outside-click test was skipped: Accessibility permission unavailable to `osascript`.

### 2026-08-04 — Implement clipboard macOS MVP

**What was done**

- Created SwiftUI/AppKit macOS project.
- Added pasteboard polling/filtering, dedupe, local JSON history, images, file bookmarks, global hotkey, picker panel, target-app paste, settings, and Accessibility fallback.
- Generated premium clipboard icon and added macOS asset variants plus `.icns`.

**Files changed**

- `clipboard.xcodeproj/`
- `clipboard/`
- `clipboardTests/`
- `README.md`, `.gitignore`, `LICENSE`, `docs/roadmap.md`, `docs/summary.md`

**Commands run**

- `xcode-select -p`
- `xcodebuild -version`
- `xcodebuild -showsdks`
- icon generation/conversion commands
- `xcodebuild ... test`
- `xcodebuild ... build`
- `open -g .../clipboard.app`

**Validation**

- 8/8 tests passed.
- Debug build passed.
- Smoke launch passed without clipboard mutation.

**Git**

- Commit: `2990e75` implementation; `b2d5111` publication record; `567ca9b` artifact ignore.
- Push status: public `Kelsiito/clipboard`; remote SHA verified after each push.

**Notes / risks**

- Accessibility permission required for automatic paste.
- Unsigned local build only.
