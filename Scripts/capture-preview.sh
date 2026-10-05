#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_dir="${PILI_TEST_RESULTS:-$project_root/build/tests}"
device_id="$(xcrun simctl list devices booted -j | python3 -c '
import json,sys
devices=[v for vs in json.load(sys.stdin)["devices"].values() for v in vs if v["state"]=="Booted" and "iPhone" in v["name"]]
if not devices: raise SystemExit("No booted iPhone simulator after tests")
print(devices[-1]["udid"])
')"
app_path="$result_dir/DerivedData/Build/Products/Debug-iphonesimulator/bili.app"
test -d "$app_path"
mkdir -p "$project_root/dist"
xcrun simctl install "$device_id" "$app_path"
xcrun simctl status_bar "$device_id" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl ui "$device_id" appearance light
xcrun simctl launch --terminate-running-process "$device_id" io.github.syiar.PiliPlusSwift
sleep 5
xcrun simctl io "$device_id" screenshot "$project_root/dist/preview-light.png"
xcrun simctl ui "$device_id" appearance dark
sleep 2
xcrun simctl io "$device_id" screenshot "$project_root/dist/preview-dark.png"
