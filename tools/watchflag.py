# lldb: find who writes CoreMedia`sDisableRegistryCodesignValidation.
#   lldb --batch -o "command script import watchflag.py" -o "watchflag <exe> <args...>"
import lldb

def watchflag(debugger, command, result, d):
    args = command.split()
    t = debugger.CreateTarget(args[0])
    t.BreakpointCreateByName("VTCopyVideoDecoderList")
    debugger.SetAsync(False)
    err = lldb.SBError()
    li = lldb.SBLaunchInfo(args[1:])
    p = t.Launch(li, err)
    sym = t.FindSymbols("sDisableRegistryCodesignValidation")
    addr = sym[0].GetSymbol().GetStartAddress().GetLoadAddress(t)
    print(f"flag @ {addr:#x}")
    w = t.WatchAddress(addr, 1, False, True, err)
    print("watch", err)
    for _ in range(4):
        p.Continue()
        if p.GetState() != lldb.eStateStopped:
            break
        th = p.GetSelectedThread()
        print("stop:", th.GetStopDescription(200))
        for i in range(min(6, th.GetNumFrames())):
            f = th.GetFrameAtIndex(i)
            print(f"  #{i} {f.GetPC():#x} {f.GetModule().GetFileSpec().GetFilename()}`{f.GetFunctionName()}")
        f0 = th.GetFrameAtIndex(0)
        insts = t.ReadInstructions(lldb.SBAddress(f0.GetPC() - 0x50, t), 40)
        for ins in insts:
            print(f"    {ins.GetAddress().GetLoadAddress(t):#x} {ins.GetMnemonic(t)} {ins.GetOperands(t)}  {ins.GetComment(t)}")
    p.Kill()

def __lldb_init_module(debugger, d):
    debugger.HandleCommand("command script add -f watchflag.watchflag watchflag")
