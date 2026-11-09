#!/bin/zsh
# zsh is required: this is a macOS installer/build script. Google Shell
# Style permits a non-bash interpreter when the execution environment
# forces it (https://google.github.io/styleguide/shellguide.html).
#
# install.sh — copy the two VCN plug-ins into /Library/Video/Plug-Ins.
#
# This is the ONLY filesystem step needed: it does not touch the sealed system
# volume, does not use authenticated-root, and does not touch the EFI. The kext
# (VCNVTLoader.kext) and Lilu are loaded by OpenCore; you do those steps in the
# EFI yourself.
#
# Usage:
#   ./install.sh              install (re-launches itself with sudo)
#   ./install.sh --uninstall  remove the bundles from /Library/Video/Plug-Ins
#   ./install.sh --check      only verify cdhashes, copy nothing
#
set -e
cd "${0:A:h}"

DEST=/Library/Video/Plug-Ins
[[ "$DEST" == "/Library/Video/Plug-Ins" ]] || {
  echo "unexpected destination: $DEST" >&2
  exit 1
}
AV1_SRC=../vtav1/build/AV1VCNDecoder.bundle
VP9_SRC=../vtvp9/build/VP9VCNDecoder.bundle
BUNDLES=("$AV1_SRC" "$VP9_SRC")

mode=install
case "${1:-}" in
  --uninstall) mode=uninstall ;;
  --check)     mode=check ;;
  "" )         ;;
  *) echo "usage: $0 [--uninstall|--check]"; exit 2 ;;
esac

# full sha256 cdhash (64 hex) a bundle is actually signed with
live_cdhash() {
  codesign -dvvv "$1" 2>&1 | awk -F= '/CandidateCDHashFull sha256/{print $2}' | tr -d ' \n'
}
# the cdhash baked into cdhashes.h for that array (0x44, 0xc3, ... -> 44c3...)
baked_cdhash() {  # $1 = kCdhashAV1 | kCdhashVP9
  awk -v want="$1" '
    $0 ~ ("uint8_t " want "\\[\\]") {
      sub(/.*\{/, ""); sub(/\}.*/, "");   # keep only what is between the braces
      gsub(/0x/, ""); gsub(/[^0-9a-f]/, ""); print; exit
    }' cdhashes.h
}

# --- verification: the installed bundles must match the kext allowlist ---
check_cdhashes() {
  local ok=1
  local -A arr=( "$AV1_SRC" kCdhashAV1  "$VP9_SRC" kCdhashVP9 )
  for b in "${BUNDLES[@]}"; do
    [[ -d "$b" ]] || { echo "  MISSING: $b"; ok=0; continue; }
    local live="$(live_cdhash "$b")"
    local baked="$(baked_cdhash "${arr[$b]}")"
    if [[ -z "$live" ]]; then
      echo "  ?  $b: could not read cdhash (codesign)"; ok=0
    elif [[ "${live:l}" == "${baked:l}" ]]; then
      echo "  OK $b  (${live:0:16}…)"
    else
      echo "  MISMATCH $b"
      echo "     bundle:     ${live:l}"
      echo "     cdhashes.h: ${baked:l}"
      echo "     -> you rebuilt the plug-in: run ./gen_cdhashes.sh and ./build.sh again,"
      echo "        then reinstall the kext in the EFI."
      ok=0
    fi
  done
  return $((1-ok))
}

if [[ "$mode" == check ]]; then
  echo "verifying cdhashes against cdhashes.h…"
  check_cdhashes && echo "all match." || { echo "there are differences (see above)."; exit 1; }
  exit 0
fi

# from here on we write to /Library -> root
if [[ $EUID -ne 0 ]]; then
  echo "root is required to write to $DEST; re-launching with sudo…"
  exec sudo "$0" "$@"
fi

if [[ "$mode" == uninstall ]]; then
  for b in AV1VCNDecoder.bundle VP9VCNDecoder.bundle; do
    if [[ -d "$DEST/$b" ]]; then rm -rf -- "$DEST/$b" && echo "removed $DEST/$b"
    else echo "not present: $DEST/$b"; fi
  done
  echo
  echo "Done. Remaining (you do this in the EFI): remove VCNVTLoader.kext from"
  echo "Kernel>Add in config.plist and reboot."
  exit 0
fi

# install
echo "verifying cdhashes before copying…"
check_cdhashes || { echo; echo "ABORTING: cdhashes do not match the kext (see above)."; exit 1; }

mkdir -p "$DEST"
for b in "${BUNDLES[@]}"; do
  name="${b:t}"
  [[ "$name" == "AV1VCNDecoder.bundle" || "$name" == "VP9VCNDecoder.bundle" ]] || {
    echo "refusing unexpected bundle: $name" >&2
    exit 1
  }
  rm -rf -- "$DEST/$name"
  cp -R "$b" "$DEST/$name"
  chown -R root:wheel "$DEST/$name"
  chmod -R go-w "$DEST/$name"
  echo "installed $DEST/$name"
done

echo
echo "Bundles installed in $DEST."
echo
echo "Remaining (you do this; the script does NOT touch the EFI):"
echo "  1. Copy VCNVTLoader.kext (and Lilu.kext if missing) to EFI/OC/Kexts."
echo "  2. Add them to Kernel>Add in config.plist AFTER Lilu"
echo "     (and after AMFIPass if you use it; AMFIPass is optional)."
echo "  3. Keep an OpenCore boot entry WITHOUT the kext in case of a panic."
echo "  4. Reboot. You can drop amfi_get_out_of_my_way from boot-args."
echo
echo "Verify: VTIsHardwareDecodeSupported(av01)=1 and (vp09)=1, 4K YouTube in Safari."
