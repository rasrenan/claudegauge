#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Release of claudeGauge and packages
# it as build/ClaudeGauge.dmg: the app, an Applications shortcut and
# "How to install.txt", laid out side by side in the Finder window.
#
# The app is ad-hoc signed (no paid Apple Developer ID), so people who download
# it must allow it once in System Settings > Privacy & Security > Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP_NAME=ClaudeGauge
VOLUME_NAME=claudeGauge
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ClaudeGauge/Info.plist)
DMG="build/${APP_NAME}.dmg"
STAGE="build/dmg-stage"
RW_DMG="build/${APP_NAME}-rw.dmg"

echo "Building claudeGauge ${VERSION} (universal)…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release \
    -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build >/dev/null
APP="build/Build/Products/Release/${APP_NAME}.app"

echo "Staging…"
rm -rf "$STAGE" "$DMG" "$RW_DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/claudeGauge.app"
ln -s /Applications "$STAGE/Applications"
cp "packaging/How to install.txt" "$STAGE/"

echo "Creating disk image…"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Lay out the Finder window: app on the left, Applications on the right,
# instructions underneath. Needs permission to control Finder; if that is
# refused the image still works, just without the tidy layout.
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
if osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set position of item "claudeGauge.app" of container window to {160, 150}
        set position of item "Applications" of container window to {500, 150}
        set position of item "How to install.txt" of container window to {330, 330}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "Finder layout applied."
else
    echo "warning: could not set the Finder layout (Finder automation not allowed); continuing." >&2
fi
sync
hdiutil detach -quiet "$MOUNT_DIR"

hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW_DMG" "$STAGE"

echo "Done: $DMG (claudeGauge ${VERSION})"
