# Installer Core

`installer/app/main.swift` is a thin SwiftUI shell over `installer/engine.sh`. The engine provides `check`, `install [--force]`, `repair [--force]`, and `uninstall`; only preflight is unprivileged.

- `validated-builds.json` records macOS builds whose AMD AV1 and VP9 driver paths were checked. Informational GPU-test fields do not replace layout validation.
- `build-app.sh` embeds the already-built AV1/VP9 bundles without changing their cdhashes, then signs the outer app. Locally rebuilt decoders naturally have different cdhashes from released bundles.
- `make-dmg.sh` packages the app; release CI verifies x86_64 binaries and the app's deep strict signature before creating a SHA-256 checksum.
- `/System/Library/Video/Plug-Ins` is the current installation target because `/Library` requires Apple signatures and the CoreMedia runtime patch is not reliable on Tahoe.
- Repair restores only missing Apple plug-ins from the matching sealed snapshot. Recursive deletion is restricted to the two decoder bundle destinations.

Privileged command construction, exact deletion guards and driver validation are security invariants described in `mem:security`.
