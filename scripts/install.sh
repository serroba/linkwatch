#!/usr/bin/env bash
# Install or update LinkWatch from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/serroba/linkwatch/main/scripts/install.sh | bash
#   bash scripts/install.sh [--version 0.2.0] [--dir ~/Applications]
#
# Downloads the release zip, verifies its SHA-256 against the published checksum,
# quits a running LinkWatch, replaces the app and relaunches it.
set -euo pipefail

repository="serroba/linkwatch"
version=""
destination=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2#v}"; shift 2 ;;
    --dir) destination="$2"; shift 2 ;;
    *) echo "Usage: install.sh [--version X.Y.Z] [--dir DIRECTORY]" >&2; exit 64 ;;
  esac
done

if [[ "$(uname -s)" != Darwin ]]; then
  echo "LinkWatch runs on macOS only." >&2
  exit 69
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]]; then
  echo "LinkWatch needs macOS 14 or later." >&2
  exit 69
fi

if [[ -z "$version" ]]; then
  version="$(curl -fsSL "https://api.github.com/repos/$repository/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "$version" ]] || { echo "Could not find the latest release." >&2; exit 69; }
fi
if [[ -z "$destination" ]]; then
  if [[ -w /Applications ]]; then destination="/Applications"; else destination="$HOME/Applications"; fi
fi
mkdir -p "$destination"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="LinkWatch-$version.zip"
base="https://github.com/$repository/releases/download/v$version"
echo "Downloading LinkWatch $version…"
curl -fsSL --proto '=https' -o "$work/$archive" "$base/$archive"
curl -fsSL --proto '=https' -o "$work/$archive.sha256" "$base/$archive.sha256"
expected="$(cut -d' ' -f1 < "$work/$archive.sha256")"
actual="$(shasum -a 256 "$work/$archive" | cut -d' ' -f1)"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "Checksum mismatch; not installing." >&2
  exit 1
fi
ditto -x -k "$work/$archive" "$work/unpacked"
[[ -d "$work/unpacked/LinkWatch.app" ]] || { echo "The archive has no LinkWatch.app." >&2; exit 1; }

if pgrep -x LinkWatch > /dev/null; then
  echo "Quitting the running LinkWatch…"
  osascript -e 'quit app "LinkWatch"' > /dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x LinkWatch > /dev/null || break; sleep 0.5; done
  pkill -x LinkWatch 2> /dev/null || true
fi
rm -rf "$destination/LinkWatch.app"
ditto "$work/unpacked/LinkWatch.app" "$destination/LinkWatch.app"
echo "Installed LinkWatch $version in $destination."
open "$destination/LinkWatch.app"
echo "LinkWatch is running in the menu bar. On first use, allow Location (Settings in the panel)"
echo "and Local Network access; see docs/user-guide.md in the repository."
