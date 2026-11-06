#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/RemoteShade.app"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
clang -fmodules -I "$ROOT/Vendor/m1ddc/headers" "$ROOT"/Vendor/m1ddc/sources/*.m "$ROOT/Sources/Helpers/DDCBrightness.m" -framework CoreDisplay -o "$APP/Contents/Helpers/remoteshade-ddc"
cp "$ROOT/Vendor/m1ddc/LICENSE" "$APP/Contents/Resources/m1ddc-LICENSE.txt"
ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Helpers/remoteshade-ddc"
xcrun swiftc -target "$(uname -m)-apple-macosx${MACOSX_DEPLOYMENT_TARGET}" -swift-version 5 -O -framework AppKit -framework IOKit "$ROOT"/Sources/App/*.swift "$ROOT"/Sources/Display/*.swift "$ROOT"/Sources/System/*.swift "$ROOT"/Sources/Policy/*.swift -o "$APP/Contents/MacOS/RemoteShade"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>cn.leaflab.display-guard</string>
<key>CFBundleName</key><string>RemoteShade</string>
<key>CFBundleExecutable</key><string>RemoteShade</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.14</string>
<key>CFBundleVersion</key><string>20</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
