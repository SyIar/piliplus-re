#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_dir="${PILI_TEST_RESULTS:-$project_root/build/tests}"
mkdir -p "$result_dir"
device_id="$(xcrun simctl list devices available -j | python3 -c '
import json,re,sys
d=json.load(sys.stdin)
devices=[]
for runtime, values in d["devices"].items():
    if "iOS" not in runtime: continue
    version=tuple(int(n) for n in re.findall(r"\d+", runtime))
    for device in values:
        if not device.get("isAvailable") or "iPhone" not in device["name"]: continue
        model=re.search(r"iPhone (\d+)", device["name"])
        rank=(version, int(model[1]) if model else 0, "Pro" in device["name"])
        devices.append((rank, device["udid"]))
if not devices: raise SystemExit("No available iPhone simulator")
print(max(devices)[1])
')"
case "${1:-all}" in
  build) test_action=build-for-testing; result_name=TestBuild ;;
  run) test_action=test-without-building; result_name=PiliPlusSwift ;;
  all) test_action=test; result_name=PiliPlusSwift ;;
  *) echo 'Usage: test-ios.sh [build|run|all]' >&2; exit 2 ;;
esac
if [ "$test_action" = test-without-building ] && [ -f "$result_dir/simulator-id.txt" ]; then
  device_id="$(cat "$result_dir/simulator-id.txt")"
fi
printf '%s\n' "$device_id" > "$result_dir/simulator-id.txt"
if [ "$test_action" != build-for-testing ]; then
  # A single prebooted simulator avoids the runner's failing parallel clones.
  python3 - "$device_id" <<'PY'
import subprocess,sys
device=sys.argv[1]
subprocess.run(["xcrun", "simctl", "boot", device], check=False, timeout=60)
# A clean hosted runtime performs Data Migration before SpringBoard is ready.
# The observed runner took 192 seconds; keep this bounded without rejecting a healthy first boot.
subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=600)
PY
fi
xcodebuild "$test_action" \
  -project "$project_root/bili.xcodeproj" -scheme bili \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$result_dir/DerivedData" \
  -resultBundlePath "$result_dir/$result_name.xcresult" \
  -only-testing:biliTests \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -destination-timeout 180 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
