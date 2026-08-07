# Release checklist

`clipboard` is currently source-first and unsigned. This document defines the path from a validated source build to a public macOS binary release without putting credentials or private data in the repository.

## Current status

- GitHub repository: [`Kelsiito/clipboard`](https://github.com/Kelsiito/clipboard)
- Default branch: `main`
- CI: macOS test and build workflow on pushes and pull requests
- Source release: `v1.0.0` published without binary assets
- Binary release: not published
- Signing identity for the release pipeline: not configured

## Pre-release checks

```sh
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' test
xcodebuild -project clipboard.xcodeproj -scheme clipboard -destination 'platform=macOS' build
git diff --check
```

Also complete the manual checklist in [CONTRIBUTING.md](../CONTRIBUTING.md) with synthetic, non-sensitive data.

## Signed and notarized DMG

Requires an Apple Developer account and a Developer ID Application certificate. Keep all credentials in the local keychain or CI secret storage; never commit them.

1. Archive the exact commit intended for release with the `clipboard` scheme.
2. Sign the app with the Developer ID Application identity.
3. Create a DMG containing the signed app with `hdiutil`.
4. Submit the DMG to Apple with `xcrun notarytool`, using a keychain profile or CI secret.
5. Staple the notarization ticket with `xcrun stapler`.
6. Verify with `spctl`, `codesign`, and a clean Mac or VM.
7. Generate a SHA-256 checksum and keep it with the release notes.

Example command shape only; replace placeholders locally and never commit their values:

```sh
xcrun notarytool submit Clipboard-<version>.dmg --keychain-profile <profile> --wait
xcrun stapler staple Clipboard-<version>.dmg
spctl --assess --type open --context context:primary-signature Clipboard-<version>.dmg
shasum -a 256 Clipboard-<version>.dmg
```

## GitHub Release

For a source release, tag the validated commit and state clearly that no installable binary is attached. For a binary release, create the tag only after the signed DMG, checksum, changelog entry, and CI results are verified. Attach the DMG and checksum, include macOS requirements and permissions, and state that history remains local.

Do not publish a source-only binary claim. If signing or notarization is unavailable, keep the release as a draft or defer it.

## Homebrew Cask

Add a cask only after a stable public DMG URL and checksum exist. The cask should install the app, expose the correct version, and include the required macOS minimum. The cask belongs in an appropriate Homebrew tap or upstream Homebrew Cask contribution; it should not point to a local path or an unsigned temporary artifact.

## Privacy and rollback

- Never upload clipboard history, screenshots, logs, credentials, or local support data.
- Test the signed artifact with empty/synthetic history.
- Keep the previous release available for rollback.
- Document known Accessibility and Screen Recording permission behavior in release notes.
