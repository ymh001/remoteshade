#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-standalone.sh"
APP="$ROOT/build/RemoteShade.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/remoteshade-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$ROOT/release"
ditto "$APP" "$STAGING/RemoteShade.app"
ln -s /Applications "$STAGING/Applications"
DMG="$ROOT/release/RemoteShade-$VERSION.dmg"
hdiutil create -volname "RemoteShade $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT/release" && shasum -a 256 "RemoteShade-$VERSION.dmg" > "RemoteShade-$VERSION.dmg.sha256")
