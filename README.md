# clipboard

Clipboard history app for macOS.

`clipboard` watches the general pasteboard, keeps local text/images/file references, and opens a simple Windows+V-style picker with `⌘⇧V`.
It runs as a menu-bar-only app, like Amphetamine, with no Dock presence.
The picker shows three rows at once; scroll for older entries, or use the pin button/context menu to keep up to three favourites at the top.

## Requirements

- macOS 14+
- Xcode with macOS SDK

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

Click the `×` button, click outside the picker, or paste an item to close it. When Accessibility is available, the picker opens above the active text field/selection; without it, the picker falls back to the screen centre.

## Validation

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
```

## License

MIT.
