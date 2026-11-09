# Tech Stack

- Platform: Darwin/macOS, x86_64 only; Xcode Command Line Tools required. Decoder build scripts target macOS 13+, while the installer supports macOS Sequoia 15 through Tahoe 26.
- C: AV1/VP9 parsers, VCN submission, VideoToolbox plug-ins and test drivers. VP9 builds explicitly as C11.
- C++: Lilu kernel extensions. `KEXT_SDK` must provide Lilu headers/library and MacKernelSDK.
- Swift: SwiftUI/AppKit installer, WebKit test shell, asset renderer and VideoToolbox probes.
- Shell: zsh for macOS-specific build/install scripts; Bash where portable. JSON holds validated driver builds.
- Python: reverse-engineering/LLDB tools; formatter target is Python 3.11 (`pyproject.toml`). No Python package manager or lockfile is used.
- Vanilla JavaScript/HTML/CSS: userscript and local browser tests; no Node build or dependency tree. Node is only useful for syntax checks.
- Apple frameworks: CoreFoundation, CoreMedia, CoreVideo, VideoToolbox, IOKit, IOSurface; some tools also use CoreGraphics, ImageIO, AppKit and WebKit.
- CI/release: GitHub Actions on `macos-15`; decoder builds, app verification, DMG creation and SHA-256 checksum. Third-party actions must remain pinned by full commit SHA.
- Not vendored: Apple binaries, IDA databases, conformance vectors and browser test videos. `vcnvp9/ac_vcn_vp9_default.h` is AMD/Mesa-derived MIT code; preserve its license.
