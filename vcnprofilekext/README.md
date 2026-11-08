# VCNVideoProfile

A Lilu plugin that runs Navi 21 on the VIDEO workload profile, the one Linux uses while VCN is active, instead of the COMPUTE profile macOS sets. It is a measurement tool, not part of the decoder installer.

## Why a kext

`AMDRadeonX6000Framebuffer`'s Info.plist sets `PP_WorkLoadPolicyMask=16`, and the driver copies it onto the GPU's registry entry at start. A device property with the same name gets overwritten. The plugin answers the registry read itself instead.

## Install

1. Build with `./build.sh`.
2. Copy `build/VCNVideoProfile.kext` to `EFI/OC/Kexts`.
3. Add it to `Kernel > Add` after `Lilu.kext` and reboot.

## Boot args

| Arg | Effect |
|---|---|
| `-vcnvpoff` | Plugin does nothing |
| `vcnwlmask=N` | Uses mask N, 1 to 127, instead of 4 (VIDEO) |

## Check it worked

`ioreg` keeps showing 16, because only the value the driver reads changes. The plugin's log lines don't show up in `log show`, and `dmesg` has usually overwritten them by the time you can read it.

Probe the function that sends the mask to the firmware instead, then run a video decode while it waits (needs a `csr-active-config` that allows DTrace):

```bash
sudo dtrace -qn 'fbt::*smu_11_0_7_set_workload_policy:entry { printf("requested mask %u\n", *(uint32_t *)arg1); }'
```

Expected: `requested mask 4`. A value of 16 means the driver is still on COMPUTE.

## Limits

It only acts on Darwin 25.6 (macOS 26.7.x), the build its function signatures were read from. On any other version it logs a line and does nothing. If a symbol is missing, the driver is left as it is.

## Remove

Delete the `Kernel > Add` entry and the kext from `EFI/OC/Kexts`, then reboot.
