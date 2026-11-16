#!/usr/bin/env bash
# Build claudeGauge in Release mode and install it to /Applications.
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP_NAME=ClaudeGauge
BUILT_APP="build/Build/Products/Release/${APP_NAME}.app"
INSTALLED_APP="/Applications/${APP_NAME}.app"

if [ ! -d /Applications/Xcode.app ]; then
    echo "error: Xcode is required but /Applications/Xcode.app was not found." >&2
    echo "Install Xcode from the App Store, then run this script again." >&2
    exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
    if [ ! -d "${APP_NAME}.xcodeproj" ] || [ project.yml -nt "${APP_NAME}.xcodeproj" ]; then
        xcodegen generate
    fi
fi

xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Release -derivedDataPath build build

pkill -x "${APP_NAME}" || true

rm -rf "${INSTALLED_APP}"
cp -R "${BUILT_APP}" "${INSTALLED_APP}"
open "${INSTALLED_APP}"

echo "claudeGauge installed. Click the gauge in the menu bar → Launch at login to start it with your Mac."
