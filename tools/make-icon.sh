#!/usr/bin/env bash
# Regenerates ClaudeGauge/Assets.xcassets/AppIcon.appiconset from tools/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SET=ClaudeGauge/Assets.xcassets/AppIcon.appiconset
mkdir -p "$SET"

MASTER="$SET/icon_1024.png"
swift tools/make-icon.swift "$MASTER"

images=""
for pt in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((pt * scale))
        name="icon_${pt}x${pt}@${scale}x.png"
        if [ "$px" -eq 1024 ]; then cp "$MASTER" "$SET/$name"; else sips -z "$px" "$px" "$MASTER" --out "$SET/$name" >/dev/null; fi
        images="$images{\"idiom\":\"mac\",\"size\":\"${pt}x${pt}\",\"scale\":\"${scale}x\",\"filename\":\"$name\"},"
    done
done
rm "$MASTER"

printf '{"images":[%s],"info":{"version":1,"author":"xcode"}}\n' "${images%,}" > "$SET/Contents.json"
printf '{"info":{"version":1,"author":"xcode"}}\n' > ClaudeGauge/Assets.xcassets/Contents.json
echo "AppIcon regenerated in $SET"
