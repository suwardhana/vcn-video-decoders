# lldb: log the order of AVD ScheduleAVDCommands / QueryAVDCommandStatus calls (refcons, wait flag)
# made inside a process, to see how many commands the driver's own client keeps in flight.
#   lldb --batch -o "command script import seqtrace.py" -o "process attach --name VTDecoderXPCService --waitfor" -o "seqtrace 80"
import lldb, struct, time

STATE = {"n": 0, "max": 80, "pending": {}, "t0": None}

def rd(proc, addr, n):
    err = lldb.SBError()
    b = proc.ReadMemory(addr, n, err)
    return b if err.Success() else None

def on_sched(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    rdx = frame.FindRegister("rdx").GetValueAsUnsigned()  # AVD_RefConList {count, pad, refcons**}
    th = frame.GetThread()
    # read refcons after the call returns: step out
    th.StepOut()
    hdr = rd(proc, rdx, 16)
    refs = []
    if hdr:
        cnt, _, ptr = struct.unpack("<IIQ", hdr)
        arr = rd(proc, ptr, 8 * min(cnt, 8)) or b""
        refs = [hex(x) for x in struct.unpack(f"<{len(arr)//8}Q", arr)]
    log(f"SCHED -> refcons {refs} (thread {th.GetThreadID():#x})")
    return False

def on_query(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    rsi = frame.FindRegister("rsi").GetValueAsUnsigned()  # {count, pad, entries*}
    hdr = rd(proc, rsi, 16)
    out = []
    if hdr:
        cnt, _, ptr = struct.unpack("<IIQ", hdr)
        for i in range(min(cnt, 8)):
            e = rd(proc, ptr + 24 * i, 24)
            if e:
                ref, unk, wait, st, st2 = struct.unpack("<QIIII", e)
                out.append(f"{ref:#x}/wait={wait}")
    log(f"QUERY {out} (thread {frame.GetThread().GetThreadID():#x})")
    return False

def log(msg):
    if STATE["t0"] is None:
        STATE["t0"] = time.time()
    STATE["n"] += 1
    print(f"{(time.time()-STATE['t0'])*1000:8.1f}ms {msg}", flush=True)
    if STATE["n"] >= STATE["max"]:
        raise SystemExit

def seqtrace(debugger, command, result, d):
    STATE["max"] = int(command or 80)
    t = debugger.GetSelectedTarget()
    for pat, fn in [(r"ScheduleAVDCommands", "seqtrace.on_sched"), (r"QueryAVDCommandStatus", "seqtrace.on_query")]:
        bp = t.BreakpointCreateByRegex(pat, "AMDRadeonVADriver2")
        bp.SetScriptCallbackFunction(fn)
        print(pat, bp.GetNumLocations(), "locations", flush=True)
    debugger.SetAsync(False)
    p = t.GetProcess()
    try:
        while p.IsValid() and STATE["n"] < STATE["max"]:
            p.Continue()
            if p.GetState() not in (lldb.eStateStopped, lldb.eStateRunning):
                break
    except SystemExit:
        pass
    p.Detach()

def __lldb_init_module(debugger, d):
    debugger.HandleCommand("command script add -f seqtrace.seqtrace seqtrace")
