# lldb dry run: let AMDRadeonVADriver2 build the AV1 VCN command, dump it, and kill the process
# BEFORE VAContext::submitDataBuffers reaches the kernel.
#   lldb --batch -o "command script import dryrun.py" -o "dryrun <out_dir> <decode_ivf> <args...>"
import lldb, os, struct

STATE = {"msg": None, "out": None, "trap_ok": False, "dumped": 0}

def _kill(frame, why):
    print(f"[dryrun] KILL: {why}", flush=True)
    frame.GetThread().GetProcess().Kill()

def on_checkpoint(frame, bp_loc, extra, d):
    target = frame.GetThread().GetProcess().GetTarget()
    trap = STATE["trap_bp"]
    n = trap.GetNumResolvedLocations()
    print(f"[dryrun] checkpoint: submit trap resolved locations = {n}", flush=True)
    if n < 1:
        _kill(frame, "kernel-submission trap not armed")
        return True
    STATE["trap_ok"] = True
    return False

def on_setmsg(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    err = lldb.SBError()
    this = frame.FindRegister("rdi").GetValueAsUnsigned()
    p16 = proc.ReadPointerFromMemory(this + 16, err)
    r9 = proc.ReadPointerFromMemory(p16 + 88, err)
    msg = proc.ReadPointerFromMemory(r9 + 224, err)
    STATE["msg"] = msg
    STATE["params"] = frame.FindRegister("rsi").GetValueAsUnsigned()
    print(f"[dryrun] SetDecodeMessageFields this={this:#x} msgbuf={msg:#x}", flush=True)
    return False

def on_submit(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    err = lldb.SBError()
    if STATE["dumped"]:
        return True
    if not STATE["trap_ok"]:
        th = frame.GetThread()
        bt = " <- ".join((th.GetFrameAtIndex(i).GetFunctionName() or "?") for i in range(1, min(7, th.GetNumFrames())))
        print(f"[dryrun] setup-phase submit allowed: {bt}", flush=True)
        return False
    if STATE["msg"]:
        path = os.path.abspath(os.path.join(STATE["out"], "vcn_msg.bin"))
        expr = f'(int)vcnav1_dump((void*){STATE["msg"]:#x}, 4096, "{path}")'
        opts = lldb.SBExpressionOptions()
        opts.SetIgnoreBreakpoints(True)
        opts.SetTryAllThreads(False)
        v = frame.EvaluateExpression(expr, opts)
        print(f"[dryrun] in-process dump wrote {v.GetValue()} bytes ({v.GetError()}) -> {path}", flush=True)
    else:
        print("[dryrun] submit reached but message pointer unknown", flush=True)
    STATE["dumped"] += 1
    _kill(frame, "stopping before kernel submission (dry run)")
    return True

def dryrun(debugger, command, result, d):
    args = command.split()
    STATE["out"] = args[0]
    exe, prog_args = args[1], args[2:]
    target = debugger.CreateTarget(exe)
    STATE["trap_bp"] = target.BreakpointCreateByName("VAContext::submitDataBuffers()")
    STATE["trap_bp"].SetScriptCallbackFunction("dryrun.on_submit")
    if STATE["trap_bp"].GetNumLocations() == 0:
        STATE["trap_bp"] = target.BreakpointCreateByRegex(r"^VAContext::submitDataBuffers")
        STATE["trap_bp"].SetScriptCallbackFunction("dryrun.on_submit")
    b2 = target.BreakpointCreateByRegex(r"^AvdVcnAv1DecDataProcessor::SetDecodeMessageFields")
    b2.SetScriptCallbackFunction("dryrun.on_setmsg")
    b3 = target.BreakpointCreateByName("vcnav1_dryrun_checkpoint")
    b3.SetScriptCallbackFunction("dryrun.on_checkpoint")
    env = [f"{k}={v}" for k, v in os.environ.items()] + ["VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang"]
    li = lldb.SBLaunchInfo(prog_args)
    li.SetEnvironmentEntries(env, False)
    err = lldb.SBError()
    debugger.SetAsync(False)
    proc = target.Launch(li, err)
    print(f"[dryrun] launch: {err}", flush=True)
    # breakpoints auto-continue unless a callback killed the process
    # once the command is dumped the process has been killed: never resume it (some lldb versions hang there)
    while not STATE["dumped"] and proc.IsValid() and proc.GetState() == lldb.eStateStopped:
        proc.Continue()
    print(f"[dryrun] final state={proc.GetState()} exit={proc.GetExitStatus()}", flush=True)

def __lldb_init_module(debugger, d):
    debugger.HandleCommand("command script add -f dryrun.dryrun dryrun")
