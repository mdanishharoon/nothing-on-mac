#!/usr/bin/env bash
# Builds "build/Nothing on Mac.app" for Apple Silicon and Intel.
#
#   scripts/build-app.sh          build
#   scripts/build-app.sh --open   build, then quit any running copy and launch the new one
#
# Signs with the "Nothing on Mac Self-Signed" identity when it exists (see
# create-signing-identity.sh), so macOS keeps the Bluetooth permission between builds;
# otherwise falls back to an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="Nothing on Mac Self-Signed"
app="build/Nothing on Mac.app"

swift build -c release --arch arm64 --arch x86_64
bin_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/NothingOnMac" "$app/Contents/MacOS/NothingOnMac"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp -R Resources/Fonts Resources/Images Resources/Data "$app/Contents/Resources/"

if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
  echo "Signed with \"$identity\""
else
  codesign --force --sign - "$app"
  echo "Signed ad hoc (run scripts/create-signing-identity.sh to keep permissions between builds)"
fi

echo "Built $app"
if [[ "${1:-}" == "--open" ]]; then
  pkill -x NothingOnMac 2>/dev/null || true
  pkill -x CMFBar 2>/dev/null || true
  open "$app"
fi
