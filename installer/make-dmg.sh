#!/bin/zsh
# zsh is required: this is a macOS installer/build script. Google Shell
# Style permits a non-bash interpreter when the execution environment
# forces it (https://google.github.io/styleguide/shellguide.html).
# Packages build/AMD VCN Video Decoders.app into a styled, compressed DMG for sharing.
set -e
cd "${0:A:h}"
NAME="AMD VCN Video Decoders"
APP="build/$NAME.app"
[[ -d "$APP" ]] || { echo "run build-app.sh first"; exit 1; }
VER=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
OUT="build/AMD-VCN-Video-Decoders-$VER.dmg"
WORK=$(mktemp -d)
RW="$WORK/rw.dmg"
VOL="/Volumes/$NAME"
[[ ! -e "$VOL" ]] || { echo "$VOL is already mounted; eject it first"; exit 1; }

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$NAME.app"
ln -s /Applications "$WORK/stage/Applications"
mkdir "$WORK/stage/.background"
cp assets/dmg-bg.tiff "$WORK/stage/.background/bg.tiff"

hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$NAME" -fs HFS+ -format UDRW -ov "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/{print $1; exit}')
[[ -n "$DEV" ]] || { echo "could not mount the image"; exit 1; }

# Window layout through Finder. Skip it on CI: Finder Automation can keep the image busy.
if [[ ${CI:-} != true ]]; then
  osascript <<OSA || echo "WARNING: Finder layout skipped (allow Automation for Finder to get the styled window)"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 562}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:bg.tiff"
    set position of item "$NAME.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
fi
sync
hdiutil detach -quiet "$DEV"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify -quiet "$OUT"
echo "built $OUT"
shasum -a 256 "$OUT"
