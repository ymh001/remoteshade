#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" != "--skip-build" ]]; then ./scripts/build.sh; fi
APP="$ROOT/build/remoteshade/RemoteShade.app"
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/remoteshade-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/RemoteShade.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p release
hdiutil create -volname 'RemoteShade 1.0.0' -srcfolder "$STAGE" -ov -format UDZO release/RemoteShade-1.0.0.dmg
hdiutil verify release/RemoteShade-1.0.0.dmg
(cd release && shasum -a 256 RemoteShade-1.0.0.dmg > RemoteShade-1.0.0.dmg.sha256)
