# Project Core

Hardware AV1/VP9 decoding on AMD Navi 21 through macOS VideoToolbox. CPU bitstream parsers build VCN jobs; VideoToolbox plug-ins submit them through AMD driver interfaces. Target is OpenCore hackintoshes; all build outputs are x86_64.

## Source map
- `vcnav1/`: AV1 parser, AMD VADriver interface, VCN submission, IVF test driver.
- `vcnvp9/`: VP9 parser, VCN message construction, IVF/WebM readers, test tools.
- `vtav1/`, `vtvp9/`: VideoToolbox decoder bundles and public-API test drivers.
- `installer/`: SwiftUI app, privileged shell engine, validated-driver registry, DMG packaging.
- `vcnvtkext/`: experimental Lilu kext for plug-in loading/CoreMedia and AMFI patches.
- `vcnprofilekext/`: Lilu GPU VIDEO workload-profile measurement kext.
- `tools/`: reverse-engineering and LLDB helpers; require user-supplied Apple binaries.
- `webtest/`: local MSE/media-capabilities pages; videos are external.
- `userscript/`: optional YouTube AV1 preference userscript.

For parser/plug-in data flow and hardware invariants, see `mem:decoders/core`. For installer packaging and privileged operations, see `mem:installer/core`. For kernel-module boundaries, see `mem:kexts/core`. Before modifying parsers, shell/Swift command execution, kernel patches, or web content, follow `mem:security`. Languages/build dependencies are in `mem:tech_stack`; formatting and naming are in `mem:conventions`; common commands and done-checks are in `mem:suggested_commands` and `mem:task_completion`.
