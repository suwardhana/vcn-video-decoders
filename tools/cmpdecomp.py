#!/usr/bin/env python3
# Compare two decompilation dumps function by function (addresses and auto-names normalized).
#   cmpdecomp.py a.c b.c [--show <name-substring>]
import difflib, re, sys

def load(path):
    funcs, name, buf = {}, None, []
    for line in open(path, errors="ignore"):
        m = re.match(r"//==== (0x[0-9a-f]+) (\S+)", line)
        if m:
            if name: funcs[name] = "".join(buf)
            name = demangle_key(m.group(2)); buf = []
        else:
            buf.append(line)
    if name: funcs[name] = "".join(buf)
    return funcs

def demangle_key(n):
    return n

ADDR = re.compile(r"\b(?:0x)?7[fF]{2}[0-9A-Fa-f]{6,}\b|\b(?:sub|loc|unk|byte|word|dword|qword|off|stru|asc|locret)_[0-9A-Fa-f]+\b|\bLABEL_\d+\b")
def norm(s):
    s = ADDR.sub("ADDR", s)
    s = re.sub(r"//.*", "", s)
    s = re.sub(r"\b[av]\d+\b", "V", s)        # register/variable numbering
    s = re.sub(r"\s+", " ", s)
    return s.strip()

a, b = load(sys.argv[1]), load(sys.argv[2])
show = sys.argv[sys.argv.index("--show") + 1] if "--show" in sys.argv else None
print(f"{len(a)} vs {len(b)} functions; only in A: {sorted(set(a)-set(b))[:10]}; only in B: {sorted(set(b)-set(a))[:10]}")
same, diff = [], []
for n in sorted(set(a) & set(b)):
    (same if norm(a[n]) == norm(b[n]) else diff).append(n)
print(f"identical {len(same)}, different {len(diff)}")
for n in diff:
    r = difflib.SequenceMatcher(None, norm(a[n]), norm(b[n]), autojunk=False).quick_ratio()
    print(f"  {r:5.3f} {len(a[n]):6d}/{len(b[n]):6d} {n}")
if show:
    for n in diff:
        if show in n:
            print("=" * 20, n)
            al = [re.sub(ADDR, "ADDR", l.rstrip()) for l in a[n].splitlines()]
            bl = [re.sub(ADDR, "ADDR", l.rstrip()) for l in b[n].splitlines()]
            for l in difflib.unified_diff(al, bl, "A", "B", lineterm="", n=1):
                print(l)
