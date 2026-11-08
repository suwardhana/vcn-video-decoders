# VCNVTLoader — load the VCN plug-ins (AV1 + VP9) from /Library

A Lilu plugin that lets you install the hardware decoders by **copying them to
`/Library/Video/Plug-Ins`**, without patching the sealed system volume.

## What it solves

There are two barriers to loading an adhoc VideoToolbox plug-in; this kext covers **both**, each
scoped to our two cdhashes / to the two media processes:

1. **AMFI** (kernel) refuses to map adhoc code into `com.apple.WebKit.GPU` /
   `VTDecoderXPCService`. → `kern_amfi.cpp` routes AMFI's `_library_validation_failure` and, only if
   the library's cdhash (20 bytes) is on the allowlist, returns 1 — the same value AMFI uses on its
   native *"Library Validation overridden"* path. Everything else is left intact.
2. **CoreMedia** validates the signature of `/Library` plug-ins (not `/System`). → `kern_coremedia.cpp`
   patches, in userspace and only inside those two processes, one byte of
   `figRegistryAddResultItem` (`jnz`→`jmp`) so the item is always added.

**Works with or without AMFIPass.** If you have AMFIPass (or `amfi_get_out_of_my_way`), the adhoc
library never reaches AMFI's failure path, so this kext's hook simply never fires — it is harmless
and redundant. If you don't have AMFIPass, this kext covers AMFI on its own.

Result: installing is copying the `.bundle`s to `/Library` — no authenticated-root disabled, no
sealed-volume snapshot, no global boot-arg.

## Requirements
- OpenCore with low-security boot (needed to load any unsigned kext).
- `Lilu.kext` ≥ 1.7.0 loaded before this one (order in `Kernel > Add`).
- `AMFIPass.kext` is **optional** (if present, it goes before this one; not required).
- Supported macOS versions: Sequoia 15.8.2 (24H232), Tahoe 26.7.1 (25G241) and 26.7.2 (25G332).

## Build
```
./build.sh            # produces build/VCNVTLoader.kext
```
`gen_cdhashes.sh` regenerates `cdhashes.h` from the bundles (run it if you recompile a plug-in).

## Install
```
./install.sh          # copies both bundles to /Library/Video/Plug-Ins (re-runs itself with sudo)
```
`./install.sh --check` only verifies the bundle cdhashes match `cdhashes.h` (the kext allowlist).
`./install.sh --uninstall` removes the bundles.

The script does **not** touch the EFI. You still do, yourself:
1. Copy `VCNVTLoader.kext` to the EFI, in `EFI/OC/Kexts`, and add it to `Kernel > Add` of the
   `config.plist` **after** Lilu (and after AMFIPass if you use it).
2. Keep an OpenCore boot entry **without** the kext to fall back on.
3. Reboot. You can drop `amfi_get_out_of_my_way` from boot-args: this kext (or AMFIPass) replaces it
   for our plug-ins.

## Verify
- `VTIsHardwareDecodeSupported(av01)` and `(vp09)` = 1.
- 4K AV1 and VP9 YouTube in Safari, plug-in logs, no GPU faults in the kernel log.

## Uninstall
```
./install.sh --uninstall
```
Then remove the kext from `config.plist` and reboot.

## Status
- **Complete and compiles** (`build/VCNVTLoader.kext`, Mach-O kext x86_64, adhoc signed).
- AMFI: symbols (`_library_validation_failure`, `AbstractCSBlobAccessor::cdHash`) confirmed
  identical by name in the kernelcaches of all 3 versions → Lilu resolves them by symbol, no
  per-version byte patterns.
- CoreMedia: the 11-byte pattern (`45 84 f6 4c 8b 75 c0 75 0d f6 05` → `… eb 0d f6 05`) was verified
  to occur **exactly once** in each of the 3 versions' CoreMedia, byte-identical.
- **Runtime test pending** (done by the user, with panic risk): keep an OpenCore entry without the
  kext to roll back; load the kext, move the bundles to `/Library`, reboot, and verify. 26.7.2 is
  only validated statically.
