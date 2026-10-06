#!/usr/bin/env python3
"""Repository invariants before building; Xcode remains the compiler authority."""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def require(condition, message):
    if not condition:
        raise SystemExit(message)

for relative in [
    "LICENSE", "THIRD_PARTY_NOTICES.md", "docs/FEATURE_PARITY.md",
    "docs/PILIPLUS_FEATURE_INVENTORY.md", "Licenses/ChunUI-LICENSE",
    "Packages/PiliPlaybackCore/Package.swift", "Scripts/build-ipa.sh",
    "Scripts/test-ios.sh", "Scripts/select-xcode.sh",
]:
    require((ROOT / relative).is_file(), f"Missing required file: {relative}")

info = plistlib.loads((ROOT / "Config/bili-Info.plist").read_bytes())
require(info["CFBundleDisplayName"] == "哔哩哔哩", "Unexpected app display name")
require("audio" in info.get("UIBackgroundModes", []), "Background audio mode is required")
project = (ROOT / "bili.xcodeproj/project.pbxproj").read_text()
require("io.github.syiar.PiliPlusSwift" in project, "Missing bundle identity")
for product in ["ChunUI", "PiliPlaybackCore"]:
    require(f"productName = {product};" in project, f"Missing SwiftPM product {product}")
require("b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb" in project, "ChunUI revision must be pinned")
require("mpv" not in project.lower(), "The iOS target must use AVPlayer")
language_modes = re.findall(r"SWIFT_VERSION = ([^;]+);", project)
require(len(language_modes) == 6 and set(language_modes) == {"6.0"},
        "App, unit tests and UI tests must use Swift 6 in Debug and Release")
require(project.count("SWIFT_STRICT_CONCURRENCY = complete;") == 6,
        "All Swift targets must keep complete concurrency checking")

for contents_path in (ROOT / "bili/Assets.xcassets").rglob("Contents.json"):
    contents = json.loads(contents_path.read_text())
    for item in contents.get("images", []):
        if name := item.get("filename"):
            require((contents_path.parent / name).is_file(), f"Missing asset: {contents_path.parent / name}")

for script in ["build-ipa.sh", "test-ios.sh", "select-xcode.sh", "capture-preview.sh"]:
    subprocess.run(["bash", "-n", str(ROOT / "Scripts" / script)], check=True)

tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
for name in filter(None, tracked):
    require(not re.search(r"\.(?:p12|p8|mobileprovision|provisionprofile|ipa)$", name), f"Do not commit signing or build artifacts: {name}")

if sys.platform == "darwin":
    subprocess.run(["plutil", "-lint", str(ROOT / "bili.xcodeproj/project.pbxproj")], check=True)

print("Repository validation passed; run Xcode tests and a device build next.")
