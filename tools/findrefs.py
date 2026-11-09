"""lldb: find code in a loaded image that references a C string (directly, or via a CFString literal),
or that writes/reads a given symbol, by scanning __TEXT,__text for RIP-relative operands.
lldb --batch -o "command script import findrefs.py" -o "findrefs <exe> <image> <cstring|@symbol>"
"""

from __future__ import annotations

import lldb
import struct


def findrefs(debugger, command, result, d):
    exe, image, what = command.split(None, 2)
    debugger.SetAsync(False)
    t = debugger.CreateTarget(exe)
    t.BreakpointCreateByName("main")
    err = lldb.SBError()
    p = t.Launch(lldb.SBLaunchInfo([]), err)
    mod = next(
        m for m in t.module_iter() if m.GetFileSpec().GetFilename() == image
    )
    secs = {}
    for s in mod.section_iter():
        for sub in [
            s.GetSubSectionAtIndex(i) for i in range(s.GetNumSubSections())
        ]:
            secs[sub.GetName()] = (sub.GetLoadAddress(t), sub.GetByteSize())

    def read(name):
        a, n = secs[name]
        return a, p.ReadMemory(a, n, err)

    targets = set()
    if what.startswith("@"):
        sym = t.FindSymbols(what[1:])[0].GetSymbol()
        targets.add(sym.GetStartAddress().GetLoadAddress(t))
    else:
        ca, cdata = read("__cstring")
        off = cdata.find(what.encode() + b"\0")
        cstr = ca + off
        targets.add(cstr)
        print(f"cstring @ {cstr:#x}")
        for name in secs:
            if "cfstring" in name:
                fa, fdata = read(name)
                for i in range(0, len(fdata) - 32, 8):
                    if struct.unpack_from("<Q", fdata, i + 16)[0] == cstr:
                        targets.add(fa + i)
                        print(f"CFString @ {fa + i:#x}")
    ta, text = read("__text")
    for i in range(len(text) - 7):
        disp = struct.unpack_from("<i", text, i)[0]
        for ilen_after in (
            0,
            1,
            4,
        ):  # disp32 then optional imm8/imm32 before next instruction
            tgt = ta + i + 4 + ilen_after + disp
            if tgt in targets:
                pc = ta + i
                a = lldb.SBAddress(pc, t)
                fn = a.GetSymbol().GetName()
                ins = t.ReadInstructions(lldb.SBAddress(pc - 3, t), 1)
                print(
                    f"ref @ {pc:#x} in {fn}+{pc - a.GetSymbol().GetStartAddress().GetLoadAddress(t):#x}: "
                    f"{ins[0].GetMnemonic(t) if ins.GetSize() else '?'} {ins[0].GetOperands(t) if ins.GetSize() else ''}"
                )
    p.Kill()


def __lldb_init_module(debugger, d):
    debugger.HandleCommand("command script add -f findrefs.findrefs findrefs")
