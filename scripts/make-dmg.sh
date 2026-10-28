#!/usr/bin/env bash
# Builds the designed installer disk image from an already-built app.
#
#   scripts/make-dmg.sh "build/Nothing on Mac.app" build/NothingOnMac-1.0.0.dmg
#
# Uses only built-in tools: hdiutil for the image and Finder (via AppleScript) for the window
# layout, which macOS stores in the image. The first run may ask to let your terminal control
# Finder. Icon positions must match DMGBackground in Sources/NothingOnMac/DMGArtwork.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:?usage: scripts/make-dmg.sh <app> <output.dmg>}"
dmg="${2:?usage: scripts/make-dmg.sh <app> <output.dmg>}"
volume="Nothing on Mac"
app_name="$(basename "$app")"

work="$(mktemp -d)"
cleanup() {
  hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# Background at 1x and 2x, combined into one HiDPI TIFF.
swift build
NOM_RESOURCES="$PWD/Resources" .build/debug/NothingOnMac --render-dmg-background "$work"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" 2>/dev/null

# Writable image with the app, an Applications shortcut, a hidden background and a volume icon.
staging="$work/staging"
mkdir -p "$staging/.background"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
cp "$work/background.tiff" "$staging/.background/background.tiff"

hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
hdiutil create -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDRW -size 80m -ov "$work/rw.dmg" >/dev/null
hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen -quiet


# Window: 640x420 content (plus the title bar), no toolbar, fixed icon positions.
osascript <<EOF
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 840, 588}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to false
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$app_name" of container window to {170, 196}
    set position of item "Applications" of container window to {470, 196}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

# Volume icon: the file plus the volume's "has custom icon" flag. Added after the Finder step,
# which otherwise removes it.
cp Resources/AppIcon.icns "/Volumes/$volume/.VolumeIcon.icns"
if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "/Volumes/$volume"
fi

rm -rf "/Volumes/$volume/.fseventsd"
sync
hdiutil detach "/Volumes/$volume" -quiet
rm -f "$dmg"
hdiutil convert "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
echo "Built $dmg"
