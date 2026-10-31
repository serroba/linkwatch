#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/LinkWatch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/LinkWatch" "$app_dir/Contents/MacOS/LinkWatch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
