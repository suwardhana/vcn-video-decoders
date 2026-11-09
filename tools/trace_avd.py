"""lldb script: trace AMD VA driver AVD interface calls made by AppleGVA.
Load with: command script import trace_avd.py ; then `avdtrace` after attaching.
"""

from __future__ import annotations

import lldb

# (register, [offsets to dereference in order], bytes to dump)
_DEEP = {
    "AVD_CreateAVDAccelerator": [
        ("rsi", [], 64),
        ("rsi", [8], 32),
        ("rdx", [], 96),
    ],
    "CreateDriver": [("rsi", [], 48), ("rsi", [8], 16)],
    "CreateContexts": [("rsi", [], 32), ("rsi", [0], 160)],
    "AvdVAContext::CreateContext": [("rsi", [], 96)],
    "AllocateBitstreamBufferPool": [("rsi", [], 48), ("rsi", [24], 32)],
    "GetBitstreamBufferInfo": [("rsi", [], 64)],
    "GetDriverParameter": [("rsi", [], 48), ("rsi", [8], 64)],
    "ScheduleAVDCommands": [
        ("rsi", [], 16),
        ("rsi", [8, 0], 80),
        ("rsi", [8, 0, 32], 128),
        ("rsi", [8, 0, 32, 48], 32),
        ("rdx", [], 16),
    ],
    "QueryAVDCommandStatus": [("rsi", [], 32), ("rsi", [8], 64)],
}
_DUMP = {  # function substring -> list of (register, bytes to dump)
    "CreateDriver": [("rsi", 64)],
    "CreateContexts": [("rsi", 256)],
    "GetBitstreamBufferInfo": [("rsi", 128)],
    "AllocateBitstreamBufferPool": [("rsi", 128)],
    "GetPixelBufferInfo": [("rsi", 160)],
    "AllocatePixelBufferPool": [("rsi", 160)],
    "ScheduleAVDCommands": [("rsi", 96), ("rdx", 64)],
    "QueryAVDCommandStatus": [("rsi", 64)],
    "SetContextParameter": [("rsi", 96)],
    "GetContextParameter": [("rsi", 96)],
    "SetDriverParameter": [("rsi", 96)],
    "GetDriverParameter": [("rsi", 96)],
    "AVD_CreateAVDAccelerator": [("rsi", 64)],
    "SetPictureDecodeParam": [("rdx", 8), ("rcx", 512)],
    "AvdVAContext::DecodePicture": [("rsi", 256)],
    "AvdVAContext::CreateDecoder": [],
}
_counts = {}


def hexdump(process, addr, n):
    if addr == 0 or n == 0:
        return "    (null)"
    err = lldb.SBError()
    data = process.ReadMemory(addr, n, err)
    if not err.Success():
        return f"    <unreadable {addr:#x}>"
    lines = []
    for off in range(0, len(data), 32):
        chunk = data[off : off + 32]
        words = " ".join(
            f"{int.from_bytes(chunk[i:i+8], 'little'):016x}"
            for i in range(0, len(chunk), 8)
        )
        lines.append(f"    +{off:03x}: {words}")
    return "\n".join(lines)


def on_hit(frame, bp_loc, extra_args, internal_dict):
    name = frame.GetFunctionName() or "?"
    _counts[name] = _counts.get(name, 0) + 1
    if _counts[name] > 6 and (
        "Schedule" in name
        or "Query" in name
        or "Decode" in name
        or "SetPicture" in name
    ):
        return False
    proc = frame.GetThread().GetProcess()
    regs = {
        r: frame.FindRegister(r).GetValueAsUnsigned()
        for r in ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
    }
    out = [
        f"== {name} #{_counts[name]}  "
        + " ".join(f"{k}={v:#x}" for k, v in regs.items())
    ]
    for key, specs in _DEEP.items():
        if key in name:
            for reg, path, n in specs:
                addr = regs[reg]
                err = lldb.SBError()
                for off in path:
                    addr = (
                        proc.ReadPointerFromMemory(addr + off, err)
                        if addr
                        else 0
                    )
                out.append(
                    f"  [{reg}{''.join(f'->+{o:#x}' for o in path)} = {addr:#x}]"
                )
                out.append(hexdump(proc, addr, n))
        return_now = True
    if any(k in name for k in _DEEP):
        print("\n".join(out), flush=True)
        return False
    for key, dumps in _DUMP.items():
        if key in name:
            for reg, n in dumps:
                out.append(f"  [{reg}]")
                out.append(hexdump(proc, regs[reg], n))
    print("\n".join(out), flush=True)
    return False  # auto-continue


def avdtrace(debugger, command, result, internal_dict):
    t = debugger.GetSelectedTarget()
    for pat in [
        r"^AvdVAInterface::",
        r"^AvdVAContext::(DecodePicture|CreateDecoder|SetPictureDecodeParam|CreateContext)\(",
        r"^AVD_CreateAVDAccelerator$",
    ]:
        bp = t.BreakpointCreateByRegex(pat, "AMDRadeonVADriver2")
        bp.SetScriptCallbackFunction("trace_avd.on_hit")
        print(f"bp {pat}: {bp.GetNumLocations()} locations")


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f trace_avd.avdtrace avdtrace")
