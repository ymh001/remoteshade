#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/build-standalone.sh
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.https://github.com/.proxy
export GIT_CONFIG_VALUE_0=socks5h://192.168.3.2:7890
export ALL_PROXY=socks5h://192.168.3.2:7890
export HTTPS_PROXY=socks5h://192.168.3.2:7890
xcodebuild -project App/MonitorControl.xcodeproj -scheme MonitorControl -configuration Debug -derivedDataPath build/remoteshade-derived -clonedSourcePackagesDirPath build/remoteshade-packages CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
APP="$ROOT/build/remoteshade/RemoteShade.app"
python3 - <<'COPY'
from pathlib import Path
import shutil
source=Path('build/remoteshade-derived/Build/Products/Debug/RemoteShade.app')
target=Path('build/remoteshade/RemoteShade.app')
if target.exists(): shutil.rmtree(target)
shutil.copytree(source,target,symlinks=True)
COPY
mkdir -p "$APP/Contents/Helpers"
ditto build/RemoteShade.app/Contents/Helpers/remoteshade-ddc "$APP/Contents/Helpers/remoteshade-ddc"
ditto build/RemoteShade.app/Contents/Resources/AppIcon.icns "$APP/Contents/Resources/RemoteShade.icns"
python3 - "$APP" <<'PY'
import sys,plistlib
from pathlib import Path
app=Path(sys.argv[1]);p=app/'Contents/Info.plist';d=plistlib.loads(p.read_bytes());d.pop('CFBundleIconName',None);d['CFBundleIconFile']='RemoteShade.icns';d['CFBundleDisplayName']='RemoteShade';p.write_bytes(plistlib.dumps(d))
licenses=['RemoteShade — Open source notices\n','MonitorControl\n'+Path('App/License.txt').read_text(),'m1ddc\n'+Path('Vendor/m1ddc/LICENSE').read_text()]
for package in Path('build/remoteshade-packages/checkouts').iterdir():
 for name in ['LICENSE','LICENSE.txt','License.txt','LICENSE.md']:
  license=package/name
  if license.is_file():
   licenses.append(package.name+'\n'+license.read_text());break
(app/'Contents/Resources/OpenSourceLicenses.txt').write_text('\n\n'.join(licenses))
PY
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built RemoteShade %s\n' "$APP"
