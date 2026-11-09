#!/bin/zsh
# zsh is required: this is a macOS installer/build script. Google Shell
# Style permits a non-bash interpreter when the execution environment
# forces it (https://google.github.io/styleguide/shellguide.html).
# Renders assets/AppIcon.icns and assets/dmg-bg.tiff from assets/render.swift.
set -e
cd "${0:A:h}/assets"
WORK=$(mktemp -d)
xcrun swiftc -O render.swift -o "$WORK/render"
"$WORK/render" "$WORK"
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns
tiffutil -cathidpicheck "$WORK/dmg-bg.png" "$WORK/dmg-bg@2x.png" -out dmg-bg.tiff 2>/dev/null
cp "$WORK/icon-1024.png" icon-1024.png
echo "assets ready"
