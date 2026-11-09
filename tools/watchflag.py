"""Watch writes to CoreMedia sDisableRegistryCodesignValidation.

Usage:
  lldb --batch -o "command script import watchflag.py" -o "watchflag <exe> <args...>"
"""

from __future__ import annotations

import lldb


def watchflag(
    debugger: lldb.SBDebugger,
    command: str,
    result: object,
    unused_dict: dict,
) -> None:
    """Install a watchpoint on sDisableRegistryCodesignValidation.

    Args:
      debugger: Active lldb debugger.
      command: Remaining command-line arguments.
      result: lldb command result object.
      unused_dict: Extra session dict from lldb.
    """
    del result, unused_dict  # Unused.
    args = command.split()
    target = debugger.CreateTarget(args[0])
    target.BreakpointCreateByName("VTCopyVideoDecoderList")
    debugger.SetAsync(False)
    err = lldb.SBError()
    launch_info = lldb.SBLaunchInfo(args[1:])
    process = target.Launch(launch_info, err)
    symbols = target.FindSymbols("sDisableRegistryCodesignValidation")
    addr = symbols[0].GetSymbol().GetStartAddress().GetLoadAddress(target)
    print(f"flag @ {addr:#x}")
    target.WatchAddress(addr, 1, False, True, err)
    print("watch", err)
    for _ in range(4):
        process.Continue()
        if process.GetState() != lldb.eStateStopped:
            break
        thread = process.GetSelectedThread()
        print("stop:", thread.GetStopDescription(200))
        for i in range(min(6, thread.GetNumFrames())):
            frame = thread.GetFrameAtIndex(i)
            print(
                f"  #{i} {frame.GetPC():#x} "
                f"{frame.GetModule().GetFileSpec().GetFilename()}`"
                f"{frame.GetFunctionName()}"
            )
        frame0 = thread.GetFrameAtIndex(0)
        insts = target.ReadInstructions(
            lldb.SBAddress(frame0.GetPC() - 0x50, target), 40
        )
        for inst in insts:
            print(
                f"    {inst.GetAddress().GetLoadAddress(target):#x} "
                f"{inst.GetMnemonic(target)} {inst.GetOperands(target)}  "
                f"{inst.GetComment(target)}"
            )
    process.Kill()


def __lldb_init_module(debugger: lldb.SBDebugger, unused_dict: dict) -> None:
    """Register the watchflag command with lldb."""
    del unused_dict  # Unused.
    debugger.HandleCommand(
        "command script add -f watchflag.watchflag watchflag"
    )
