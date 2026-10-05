#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="${PILI_BUILD_ROOT:-$project_root/build/PiliPlusSwift}"
build_number="${GITHUB_RUN_NUMBER:-1}"
mkdir -p "$build_root" "$project_root/dist"

xcodebuild build \
  -project "$project_root/bili.xcodeproj" \
  -scheme bili -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/DerivedData" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  ENABLE_DEBUG_DYLIB=NO

app_path="$build_root/DerivedData/Build/Products/Release-iphoneos/bili.app"
test -d "$app_path"
staging_dir="$(mktemp -d "$build_root/package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/PiliPlusSwift.app"
ipa_path="$project_root/dist/PiliPlusSwift-unsigned.ipa"
(cd "$staging_dir" && zip -qry "$staging_dir/PiliPlusSwift-unsigned.ipa" Payload)
mv -f "$staging_dir/PiliPlusSwift-unsigned.ipa" "$ipa_path"
unzip -t "$ipa_path"
(cd "$project_root/dist" && shasum -a 256 PiliPlusSwift-unsigned.ipa > SHA256SUMS.txt)
printf 'IPA: %s\n' "$ipa_path"
