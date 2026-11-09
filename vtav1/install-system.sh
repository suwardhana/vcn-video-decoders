#!/bin/zsh
# zsh is required: this is a macOS installer/build script. Google Shell
# Style permits a non-bash interpreter when the execution environment
# forces it (https://google.github.io/styleguide/shellguide.html).
# Install AV1VCNDecoder.bundle into the sealed system volume (/System/Library/Video/Plug-Ins).
#
# Why: VideoToolbox scans /Library/Video/Plug-Ins with code-signature validation that only accepts
# Apple-signed bundles (CoreMedia figRegistryAddResultItem); the bypass (figregistry_ignore_codesign)
# only works on Apple-internal builds. /System/Library/Video/Plug-Ins is scanned without validation.
#
# Requires: SIP off and authenticated-root disabled (already the case here). Needs a reboot.
# Undo:     sudo ./install-system.sh --uninstall   (or roll back the whole system volume with
#           sudo bless --mount / --last-sealed-snapshot   and reboot)
set -e
[[ "${EUID}" == 0 ]] || { echo "run with sudo"; exit 1; }
cd "${0:A:h}"
SRC=build/AV1VCNDecoder.bundle
csrutil authenticated-root status | grep -q disabled || { echo "authenticated-root must be disabled"; exit 1; }
SNAP=$(diskutil info / | awk -F': *' '/Device Node/{print $2}')   # e.g. /dev/disk3s4s1
VOL=${SNAP%s[0-9]*}                                                # e.g. /dev/disk3s4
[[ -n "${SNAP}" && "${VOL}" == /dev/disk* ]] || { echo "could not resolve system volume" >&2; exit 1; }
MNT=/System/Volumes/Update/mnt1
echo "system snapshot ${SNAP} -> volume ${VOL}, mounting at ${MNT}"
mkdir -p "${MNT}"
mount | grep -q " on ${MNT} " || mount -o nobrowse -t apfs "${VOL}" "${MNT}"
DEST="${MNT}/System/Library/Video/Plug-Ins/AV1VCNDecoder.bundle"
[[ -n "${DEST}" && "${DEST}" == "${MNT}/System/Library/Video/Plug-Ins/AV1VCNDecoder.bundle" ]] || {
  echo "refusing to touch an unexpected destination" >&2; exit 1; }
if [[ "${1:-}" == --uninstall ]]; then
  rm -rf -- "${DEST}"
  echo "removed ${DEST}"
else
  [[ -d "${SRC}" ]] || { echo "build ${SRC} first (./build.sh)"; exit 1; }
  rm -rf -- "${DEST}"
  ditto "${SRC}" "${DEST}"
  rm -rf -- "${DEST}/Contents/MacOS/AV1VCNDecoder.dSYM"
  chown -R root:wheel "${DEST}"
  chmod -R go-w "${DEST}"
  ls -la "${DEST}/Contents/MacOS"
  # the /Library copy is ignored by VideoToolbox (signature check); remove it to avoid confusion
  rm -rf -- /Library/Video/Plug-Ins/AV1VCNDecoder.bundle
fi
bless --folder "${MNT}/System/Library/CoreServices" --bootefi --create-snapshot
echo "new boot snapshot created; reboot to use it"
