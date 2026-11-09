# Security and Safety

Apply OWASP secure-design/input-validation/injection-prevention principles in every language, with project-specific binary and GPU safeguards.

## Untrusted bitstreams and memory safety
- Treat every media byte and length as hostile. Validate remaining length before subtraction, addition, pointer arithmetic, allocation or copy; check array indexes and callback pointers.
- Avoid signed-overflow and invalid-shift behavior. Bound cumulative tile sizes to their on-disk/hardware field widths; reject truncation and malformed superframe/OBU layouts.
- Check every allocation before dereference and make partial-construction cleanup safe. Preserve stack-protector, `_FORTIFY_SOURCE`, format-warning and strict-overflow hardening flags in build scripts.
- Parser changes require ASan/UBSan malformed-input coverage plus AOM/FFmpeg conformance when available; static analysis alone is insufficient.

## GPU and driver boundary
- AV1 must remain pinned to VCN instance 0; instance 1 can hang Navi 21.
- Submit only driver layouts represented by `kValidatedDrivers` / `installer/validated-builds.json`. New macOS builds require AV1 and VP9 layout validation first.
- Do not weaken test-tool GPU opt-ins: `VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang`; VP9 additionally requires `VCNVP9_ALLOW_GPU=yes-i-know-it-can-hang` and `VCNVP9_SESSION=vp9`.

## Privileged shell and Swift
- Keep root execution inside the established installer paths. Quote expansions, use strict shell modes, retain exact destination guards before every recursive deletion, and never broaden deletion to a parent plug-in directory.
- Prefer argument arrays/`Process` over shell strings. Existing shell paths use `shq`; AppleScript strings use `asq`; reject control characters in paths. Do not interpolate untrusted values into LLDB C expressions, AppleScript, `eval`, or `shell=True`.
- Validate environment-derived build/device identifiers as strictly as CLI input. Do not log credentials, authorization output containing sensitive data, or proprietary driver contents.

## Python, web and supply chain
- Use `subprocess` argument lists, explicit timeouts where hangs are possible, and `TemporaryDirectory` for generated files. Generated C/LLDB input must come only from trusted project inputs.
- Keep web DOM sinks text-based; no `eval`, `document.write`, or untrusted `innerHTML`. `webtest/index.html` and `webtest/vp9.html` use SHA-256 CSP hashes for inline script/style: never add `'unsafe-inline'`; recompute both hashes after any inline block edit and verify the page.
- Keep GitHub Actions and other dependencies pinned to reviewed immutable revisions. Download only over HTTPS and verify release artifacts with SHA-256.

For module-specific boundaries see `mem:decoders/core`, `mem:installer/core`, and `mem:kexts/core`.
