#!/bin/bash
set -euo pipefail
# Prefer the runner's stable Xcode. Never silently fall back to a pre-Liquid-Glass SDK.
selected_major="$(xcodebuild -version | awk '/^Xcode / {split($2, v, "."); print v[1]}')"
if [ "$selected_major" -lt 26 ]; then
  selected_path="$(python3 - <<'PY'
from pathlib import Path
import re
options = []
for item in Path('/Applications').glob('Xcode_*.app'):
    m = re.fullmatch(r'Xcode_(\d+(?:\.\d+)*)\.app', item.name)
    if m:
        version = tuple(map(int, m[1].split('.')))
        if version[0] >= 26:
            options.append((version, str(item / 'Contents/Developer')))
if not options:
    raise SystemExit('Xcode 26+ is required for Swift 6.2 and Liquid Glass')
print(max(options)[1])
PY
)"
  sudo xcode-select --switch "$selected_path"
fi
xcodebuild -version
xcrun swift --version
