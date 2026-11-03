#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
notchshade_stage=$(mktemp -d /private/tmp/notchshade-build.XXXXXX)
trap 'rm -rf "$notchshade_stage"' EXIT
app="$notchshade_stage/NotchShade.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -target arm64-apple-macosx13.0 -module-cache-path "$notchshade_stage/module-cache" -framework AppKit Sources/main.swift -o "$app/Contents/MacOS/NotchShade"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --keepParent "$app" build/NotchShade.zip
echo "Built build/NotchShade.zip — unzip and move NotchShade.app to Applications."
