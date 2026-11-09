# Suggested Commands

Run from the repository root.

## Build decoders and test tools
```sh
./vtav1/build.sh
./vtvp9/build.sh
./vcnav1/build.sh
./vcnvp9/build.sh
```
The plug-in scripts write bundles under their own `build/`. `vcnav1/build.sh` also builds `vtav1/vtav1test`; `vcnvp9/build.sh` builds `vp9dump` and `decode_vp9`; `vtvp9/build.sh` also builds `vtvp9test`.

## Installer
```sh
./installer/build-app.sh
./installer/make-dmg.sh
./installer/engine.sh check
sudo ./installer/engine.sh install
```
`engine.sh check` is non-privileged preflight. Install/repair/uninstall mutate the system and require explicit user intent. `VCNVT_FAKE_BUILD=<build> ./installer/engine.sh check` exercises preflight for another macOS build.

## Kernel modules
```sh
KEXT_SDK=/path/to/sdk ./vcnvtkext/build.sh
```
The SDK must contain `Lilu.kext` with headers/library and a MacKernelSDK checkout.

## Darwin-specific utilities
- Use `shasum -a 256 <file>` rather than GNU `sha256sum`.
- Use `/usr/bin/plutil` for plist edits/inspection and `codesign --verify --deep --strict <bundle>` for signature verification.
- Packaging uses `ditto` and `hdiutil`; do not substitute GNU-specific flags for their BSD/macOS equivalents.

GPU execution is opt-in for test tools; see `mem:security` before setting either allow variable.
