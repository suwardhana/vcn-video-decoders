"""lldb script: `stubs <function>` disassembles a function and prints the real target of each stub call."""

from __future__ import annotations

import lldb
import re


def resolve(target, process, addr):
    err = lldb.SBError()
    insts = target.ReadInstructions(lldb.SBAddress(addr, target), 1)
    if insts.GetSize() == 0:
        return "?"
    ins = insts.GetInstructionAtIndex(0)
    ops = ins.GetOperands(target)
    m = re.search(r"\*?(-?0x[0-9a-f]+)\(%rip\)", ops)
    if ins.GetMnemonic(target).startswith("jmp") and m:
        got = addr + ins.GetByteSize() + int(m.group(1), 16)
        dest = process.ReadPointerFromMemory(got, err)
        sym = target.ResolveLoadAddress(dest).GetSymbol()
        return sym.GetName() if sym.IsValid() else hex(dest)
    return ins.GetMnemonic(target) + " " + ops


def stubs(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    for name in command.split():
        for ctx in target.FindFunctions(name):
            fn = ctx.GetFunction() if ctx.GetFunction().IsValid() else None
            sym = ctx.GetSymbol()
            start = sym.GetStartAddress()
            end = sym.GetEndAddress()
            insts = target.ReadInstructions(
                start,
                end.GetLoadAddress(target) - start.GetLoadAddress(target)
                and 4000,
            )
            base = start.GetLoadAddress(target)
            stop = end.GetLoadAddress(target)
            print(f"== {sym.GetName()} @ {base:#x}")
            for i in range(insts.GetSize()):
                ins = insts.GetInstructionAtIndex(i)
                a = ins.GetAddress().GetLoadAddress(target)
                if a >= stop:
                    break
                if ins.GetMnemonic(target).startswith("call"):
                    ops = ins.GetOperands(target)
                    try:
                        tgt = int(ops, 16)
                        tsym = (
                            target.ResolveLoadAddress(tgt).GetSymbol().GetName()
                            or ""
                        )
                        real = (
                            resolve(target, process, tgt)
                            if "stub" in (tsym or "")
                            or "HwlIsStandardSwizzle" in tsym
                            else tsym
                        )
                    except ValueError:
                        real = ops
                    print(f"  +{a - base:#06x} call {real}")


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f resolve_stubs.stubs stubs")
