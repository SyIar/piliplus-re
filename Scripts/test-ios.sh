#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)
devices=[v for key,vs in d["devices"].items() if "iOS" in key for v in vs if v.get("isAvailable") and "iPhone" in v["name"]]
if not devices: raise SystemExit("No available iPhone simulator")
print(devices[-1]["udid"])
')"
result_dir="${PILI_TEST_RESULTS:-$project_root/build/tests}"
mkdir -p "$result_dir"
xcodebuild test \
  -project "$project_root/bili.xcodeproj" -scheme bili \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$result_dir/DerivedData" \
  -resultBundlePath "$result_dir/PiliPlusSwift.xcresult" \
  -only-testing:biliTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
