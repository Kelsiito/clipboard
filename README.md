# clipboard

Clipboard history app for macOS.

`clipboard` watches the general pasteboard, keeps local text/images/file references, and opens a simple Windows+V-style picker with `⌘⇧V`.
It runs as a menu-bar-only app, like Amphetamine, with no Dock presence.
The picker shows three rows at once; scroll for older entries, or use the pin button/context menu to keep up to three favourites at the top.

## Requirements

- macOS 14+
- Xcode with macOS SDK

On macOS 26+, the picker and settings use native Liquid Glass. macOS 14–25 keep a matching material fallback.

## Run

1. Open `clipboard.xcodeproj` in Xcode.
2. Select the `clipboard` scheme and `My Mac`.
3. Build and run.
4. Click the clipboard icon in the menu bar and choose `Definições…`; grant Accessibility when automatic paste is requested.

The app is intentionally local-only. History is stored under `~/Library/Application Support/clipboard/`. File entries store bookmarks/references; original files are never copied or deleted.

## Keyboard

- `⌘⇧V`: open history picker
- Arrow keys: navigate
- `Enter`: paste selected item
- `Esc`: close picker

Click the `×` button, click outside the picker, or paste an item to close it. On `⌘⇧V`, the app captures the target app's focused text field before activation and opens the picker above its caret/selection with a spring pop-up animation. Accessibility is requested when needed for this positioning and automatic paste; without it, the picker falls back to the target app window instead of tracking the mouse.

## Validation

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
```

## License

MIT.
