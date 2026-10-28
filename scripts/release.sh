#!/usr/bin/env bash
# Builds a release DMG.
#
#   scripts/release.sh 1.0.0             build/NothingOnMac-1.0.0.dmg
#   scripts/release.sh 1.0.0 --publish   also tags v1.0.0 and creates a GitHub release with the DMG
#
# Sets the version in Resources/Info.plist, so commit that change with the release.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh <version> [--publish]}"
publish="${2:-}"
identity="Nothing on Mac Self-Signed"
dmg="build/NothingOnMac-$version.dmg"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 1; }

plutil -replace CFBundleShortVersionString -string "$version" Resources/Info.plist
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
plutil -replace CFBundleVersion -string "$build_number" Resources/Info.plist

swift test
scripts/build-app.sh

scripts/make-dmg.sh "build/Nothing on Mac.app" "$dmg"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --sign "$identity" "$dmg"
fi
shasum -a 256 "$dmg" | tee "$dmg.sha256"
echo "Built $dmg"

if [[ "$publish" == "--publish" ]]; then
  git diff --quiet || { echo "commit your changes (including Info.plist) before publishing"; exit 1; }
  git tag "v$version"
  git push origin "v$version"
  gh release create "v$version" "$dmg" "$dmg.sha256" --title "Nothing on Mac $version" --generate-notes
fi
