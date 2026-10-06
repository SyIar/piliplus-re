#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_dir="${PILI_TEST_RESULTS:-$project_root/build/tests}"
if [ -f "$result_dir/simulator-id.txt" ]; then
device_id="$(cat "$result_dir/simulator-id.txt")"
else
device_id="$(xcrun simctl list devices booted -j | python3 -c '
import json,sys
devices=[v for vs in json.load(sys.stdin)["devices"].values() for v in vs if v["state"]=="Booted" and "iPhone" in v["name"]]
if not devices: raise SystemExit("No booted iPhone simulator after tests")
print(devices[-1]["udid"])
')"
fi
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
xcrun simctl launch --terminate-running-process "$device_id" io.github.syiar.PiliPlusSwift --ui-test-fixture glassPlayer
sleep 4
xcrun simctl io "$device_id" screenshot "$project_root/dist/preview-player-glass.png"
# simctl exports the physical display buffer in portrait orientation even when
# UIKit is in landscape. Normalize this landscape-only artifact for viewing.
player_preview="$project_root/dist/preview-player-glass.png"
player_dimensions="$(sips -g pixelWidth -g pixelHeight "$player_preview")"
player_width="$(awk '/pixelWidth:/ { print $2 }' <<< "$player_dimensions")"
player_height="$(awk '/pixelHeight:/ { print $2 }' <<< "$player_dimensions")"
if (( player_width < player_height )); then
  sips -r 270 "$player_preview" > /dev/null
fi

xcrun simctl launch --terminate-running-process "$device_id" io.github.syiar.PiliPlusSwift --ui-test-fixture subtitles
sleep 3
xcrun simctl io "$device_id" screenshot "$project_root/dist/preview-subtitles.png"

xcrun simctl launch --terminate-running-process "$device_id" io.github.syiar.PiliPlusSwift --ui-test-fixture commentTree --ui-test-reset-state
sleep 3
xcrun simctl io "$device_id" screenshot "$project_root/dist/preview-comment-tree.png"
