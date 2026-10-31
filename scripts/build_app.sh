#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/LinkWatch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/LinkWatch" "$app_dir/Contents/MacOS/LinkWatch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# A stable identity keeps macOS privacy grants (Location) across rebuilds; ad-hoc
# signatures change with every build, so each rebuild needs permission again.
identity="${LINKWATCH_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-identity -p codesigning 2>/dev/null \
  | grep -q '"LinkWatch Local Development"'; then
  identity="LinkWatch Local Development"
fi
codesign --force --sign "${identity:--}" "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s (signed %s)\n' "$app_dir" "${identity:-ad hoc}"
