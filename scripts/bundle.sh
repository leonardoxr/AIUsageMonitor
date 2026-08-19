#!/bin/bash
# Assembles dist/AIUsageMonitor.app from a release build.
#
# An .app bundle is what makes this a menu-bar-only agent (LSUIElement) and what
# SMAppService needs to register a login item. Ad-hoc signing is enough locally;
# distributing to another Mac needs a Developer ID identity in CODESIGN_IDENTITY.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="dist/AIUsageMonitor.app"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
	swift build -c release --arch arm64 --arch x86_64
	BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AIUsageMonitor"
else
	swift build -c release
	BINARY="$(swift build -c release --show-bin-path)/AIUsageMonitor"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/AIUsageMonitor"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist >"$APP/Contents/Info.plist"
cp Resources/ClaudeIcon.png Resources/CodexIcon.png "$APP/Contents/Resources/"

codesign --force --options runtime --identifier dev.xavier.AIUsageMonitor \
	--sign "$IDENTITY" "$APP" >/dev/null

echo "built $APP ($VERSION, signed with '$IDENTITY')"
