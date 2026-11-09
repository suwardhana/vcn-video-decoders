#!/bin/zsh
# zsh is required: this is a macOS installer/build script. Google Shell
# Style permits a non-bash interpreter when the execution environment
# forces it (https://google.github.io/styleguide/shellguide.html).
# Extract the VideoToolbox decoder plugins from a macOS update asset (SharedSupport.dmg payload chunks).
#   extract_plugins.sh <dir with SharedSupport.dmg> <out dir>
set -u
D="$1"; OUT="$2"
MNT=$(mktemp -d)
mkdir -p "$MNT" "$OUT"
hdiutil attach -readonly -nobrowse -mountpoint "$MNT" "$D/SharedSupport.dmg" >/dev/null || exit 1
trap 'hdiutil detach "$MNT" -quiet' EXIT
ZIP=$(find "$MNT" -name '*.zip' -size +1000000k | head -1)
TMP=$(mktemp "${TMPDIR:-/tmp}/chunk.XXXX")
for c in $(unzip -l "$ZIP" | grep -oE 'AssetData/payloadv2/payload\.[0-9]+$' | sort); do
  unzip -p "$ZIP" "$c" > "$TMP"
  hit=$(aa list -i "$TMP" 2>/dev/null | grep -E 'System/Library/Video/Plug-Ins/(AppleGVAVPXDecoder|AV1DecoderSW)\.bundle/Contents/(MacOS/|Info\.plist)')
  if [ -n "$hit" ]; then
    echo "$c:"; echo "$hit"
    for p in ${(f)hit}; do aa extract -i "$TMP" -d "$OUT" -include-path "$p" 2>/dev/null; done
  fi
  # stop once both binaries are out
  [ -f "$OUT/System/Library/Video/Plug-Ins/AppleGVAVPXDecoder.bundle/Contents/MacOS/AppleGVAVPXDecoder" ] && \
  [ -f "$OUT/System/Library/Video/Plug-Ins/AV1DecoderSW.bundle/Contents/MacOS/AV1DecoderSW" ] && break
done
rm -f "$TMP"
find "$OUT" -type f | head
