# Kernel Module Core

- `vcnvtkext/`: experimental Lilu module for loading decoders from `/Library`, including CoreMedia/AMFI-related patching. Its userspace patch approach cannot patch Tahoe's split dyld shared cache, so the installer currently uses `/System`.
- `vcnprofilekext/`: measurement-oriented Lilu module that selects the GPU VIDEO workload profile; it is not required for decoding.
- Both require an external `KEXT_SDK` containing suitable Lilu headers/library and MacKernelSDK. They are separate from the normal decoder/app build path.
- Kernel patches and binary hooks are layout- and OS-specific. Do not generalize offsets, widen AMFI bypass behavior, or enable experimental modules by default without revalidation.
- Treat userspace-to-kernel values as untrusted, preserve bounds/lifetime checks, and keep privilege reduction and system integrity implications explicit; shared rules are in `mem:security`.
