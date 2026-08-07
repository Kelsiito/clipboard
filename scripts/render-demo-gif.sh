#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FRAMES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clipboard-demo-frames.XXXXXX")
trap 'rm -rf "$FRAMES_DIR"' EXIT INT TERM

swift "$ROOT_DIR/scripts/MakeDemoGIF.swift" \
  --output "$FRAMES_DIR" \
  --icon "$ROOT_DIR/clipboard/Assets.xcassets/AppIcon.appiconset/icon-1024.png" \
  --frames 48

mkdir -p "$ROOT_DIR/docs/assets"
ffmpeg -hide_banner -loglevel error -y \
  -framerate 12 \
  -i "$FRAMES_DIR/frame-%03d.png" \
  -vf "fps=12,scale=960:600:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff:max_colors=192[p];[s1][p]paletteuse=dither=sierra2_4a" \
  -loop 0 \
  "$ROOT_DIR/docs/assets/clipboard-demo.gif"

echo "Wrote docs/assets/clipboard-demo.gif"
