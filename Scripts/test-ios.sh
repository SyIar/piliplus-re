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
case "${1:-all}" in
  build) test_action=build-for-testing; result_name=TestBuild ;;
  run) test_action=test-without-building; result_name=PiliPlusSwift ;;
  all) test_action=test; result_name=PiliPlusSwift ;;
  *) echo 'Usage: test-ios.sh [build|run|all]' >&2; exit 2 ;;
esac
xcodebuild "$test_action" \
  -project "$project_root/bili.xcodeproj" -scheme bili \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$result_dir/DerivedData" \
  -resultBundlePath "$result_dir/$result_name.xcresult" \
  -only-testing:biliTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
