#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/LinkWatch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/LinkWatch" "$app_dir/Contents/MacOS/LinkWatch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# The icon is drawn by a script rather than stored as binary artwork.
icon_dir="$(mktemp -d)"
trap 'rm -rf "$icon_dir"' EXIT
swift scripts/make_icon.swift "$icon_dir/AppIcon.iconset"
mkdir -p "$app_dir/Contents/Resources"
iconutil -c icns "$icon_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Version from LINKWATCH_VERSION (set by the release workflow from the tag), else the
# latest tag plus commit, so every build reports what it is.
version="${LINKWATCH_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo 0.0.0)}"
version="${version#v}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  -c "Set :CFBundleVersion $build" "$app_dir/Contents/Info.plist"
# A stable identity keeps macOS privacy grants (Location) across rebuilds; ad-hoc
# signatures change with every build, so each rebuild needs permission again.
identity="${LINKWATCH_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-identity -p codesigning 2>/dev/null \
  | grep -q '"LinkWatch Local Development"'; then
  identity="LinkWatch Local Development"
fi
codesign --force --sign "${identity:--}" "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s %s (signed %s)\n' "$app_dir" "$version" "${identity:-ad hoc}"
