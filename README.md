# clipboard

Clipboard history app for macOS.

`clipboard` watches the general pasteboard, keeps local text/images/file references, and opens a simple Windows+V-style picker with `⌘⇧V`.

## Requirements

- macOS 14+
- Xcode with macOS SDK

## Run

1. Open `clipboard.xcodeproj` in Xcode.
2. Select the `clipboard` scheme and `My Mac`.
3. Build and run.
4. Open `clipboard > Definições…` and grant Accessibility when automatic paste is requested.

The app is intentionally local-only. History is stored under `~/Library/Application Support/clipboard/`. File entries store bookmarks/references; original files are never copied or deleted.

## Keyboard

- `⌘⇧V`: open history picker
- Arrow keys: navigate
- `Enter`: paste selected item
- `Esc`: close picker

## Validation

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
```

## License

MIT.
