"""lldb: log every CoreFoundation/CoreMedia preference lookup (key, domain) made by a program.
lldb --batch -o "command script import prefstrace.py" -o "prefstrace <exe> <args...>"
"""

from __future__ import annotations

import lldb

_FUNCS = [
    "CFPreferencesCopyAppValue",
    "CFPreferencesGetAppBooleanValue",
    "CFPreferencesGetAppIntegerValue",
    "CFPreferencesCopyValue",
    "FigGetCFPreferenceBooleanWithDefault",
    "FigGetCFPreferenceNumberWithDefault",
    "FigCopyCFPreferenceAppValueOrOptionCFTypeWithDefault",
    "FigGetCFPreferenceDoubleWithDefault",
]
_SEEN = set()


def desc(frame, reg):
    v = frame.EvaluateExpression(f"(id)${reg}")
    s = v.GetObjectDescription()
    return s if s else hex(frame.FindRegister(reg).GetValueAsUnsigned())


def on_hit(frame, bp_loc, extra, d):
    name = frame.GetFunctionName()
    key, dom = desc(frame, "rdi"), desc(frame, "rsi")
    caller = frame.GetThread().GetFrameAtIndex(1)
    line = f"{name}({key}, {dom}) <- {caller.GetModule().GetFileSpec().GetFilename()}`{caller.GetFunctionName()}"
    if line not in _SEEN:
        _SEEN.add(line)
        print(line, flush=True)
    return False


def prefstrace(debugger, command, result, d):
    args = command.split()
    debugger.SetAsync(False)
    t = debugger.CreateTarget(args[0])
    for f in _FUNCS:
        bp = t.BreakpointCreateByName(f)
        bp.SetScriptCallbackFunction("prefstrace.on_hit")
    err = lldb.SBError()
    li = lldb.SBLaunchInfo(args[1:])
    p = t.Launch(li, err)
    while p.IsValid() and p.GetState() == lldb.eStateStopped:
        p.Continue()


def __lldb_init_module(debugger, d):
    debugger.HandleCommand(
        "command script add -f prefstrace.prefstrace prefstrace"
    )
