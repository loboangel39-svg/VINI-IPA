#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT="$ROOT/build-smoke"
APP="$OUT/WQIntegrationSmoke.app"
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun --sdk iphonesimulator clang -fobjc-arc -fmodules -arch "$ARCH" \
  -isysroot "$SDK" -mios-simulator-version-min=26.0 -O0 \
  -I Vendor/WQFiles Vendor/WQFiles/WQ*.m scripts/WQIntegrationSmoke.m \
  -framework UIKit -framework Foundation -framework Security -framework UniformTypeIdentifiers \
  -framework AVFoundation -framework AVKit -lsqlite3 -lz -o "$APP/WQIntegrationSmoke"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.3105.WQIntegrationSmoke</string>
<key>CFBundleExecutable</key><string>WQIntegrationSmoke</string>
<key>CFBundleName</key><string>WQIntegrationSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict></plist>
PLIST
cp -R ThreeOneOSFive/WQFilesResources.bundle "$APP/"
codesign --force --sign - "$APP"
echo 'Initializing CoreSimulator for the selected Xcode'
sudo xcodebuild -runFirstLaunch
# Runners may already have the service from their default Xcode running.
# Restart it after selecting another Xcode, before requesting its inventory.
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
python3 - <<'PY'
import subprocess
result = subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], capture_output=True, text=True, timeout=180, check=True)
open('build-smoke/devices.json', 'w').write(result.stdout)
PY
DEVICE=$(python3 -c 'import json; d=json.load(open("build-smoke/devices.json")); print(next(x["udid"] for runtime,items in d["devices"].items() if "iOS-26" in runtime or "iOS-27" in runtime for x in items if "iPhone" in x["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
python3 - "$DEVICE" <<'PY'
import subprocess,sys
with open('build-smoke/simulator.log', 'w') as log:
    subprocess.run(['xcrun','simctl','launch','--terminate-running-process',sys.argv[1],'org.3105.WQIntegrationSmoke'], stdout=log, stderr=subprocess.STDOUT, timeout=90, check=True)
PY
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" org.3105.WQIntegrationSmoke data)
for i in $(seq 1 90); do
  if [[ -f "$CONTAINER/Documents/integration-smoke.json" ]]; then break; fi
  sleep 2
done
test -f "$CONTAINER/Documents/integration-smoke.json"
cp "$CONTAINER/Documents/integration-smoke.json" "$OUT/"
python3 -c 'import json; d=json.load(open("build-smoke/integration-smoke.json")); print(json.dumps(d,indent=2)); assert d["passed"]'

