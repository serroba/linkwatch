#!/usr/bin/env bash
# Download a pinned release archive, verify its SHA-256 and unpack it.
set -euo pipefail
url=$1 checksum=$2 destination=$3
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
curl --fail --silent --show-error --location --proto '=https' --output "$archive" "$url"
echo "$checksum  $archive" | shasum -a 256 --check --status
mkdir -p "$destination"
unzip -q -o "$archive" -d "$destination"
