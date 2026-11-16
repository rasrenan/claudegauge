#!/usr/bin/env bash
# Regenerates the README illustrations in docs/images/ using the app's own drawing code.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT=docs/images
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Every app source except App.swift (which has @main) plus the renderer.
SOURCES=()
for f in ClaudeGauge/*.swift; do
    [ "$(basename "$f")" = "App.swift" ] || SOURCES+=("$f")
done

# Top-level code is only allowed in a file named main.swift.
cp tools/readme-images.swift "$TMP/main.swift"
swiftc -swift-version 5 -o "$TMP/readme-images" "${SOURCES[@]}" "$TMP/main.swift"
"$TMP/readme-images" "$OUT"

sips -z 256 256 ClaudeGauge/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png --out "$OUT/app-icon.png" >/dev/null
echo "README images written to $OUT"
