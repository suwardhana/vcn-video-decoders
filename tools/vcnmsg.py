#!/usr/bin/env python3
# Decode a VCN decode message buffer (as dumped by dryrun.py) using Mesa's ac_vcn_dec.h layouts.
# usage: vcnmsg.py <vcn_msg.bin> [field_filter]
import os, re, subprocess, sys, tempfile, json

HDR = os.path.join(os.path.dirname(__file__), "../.re/mesa/src/amd/common/ac_vcn_dec.h")

def layout(struct):
    h = open(HDR).read()
    m = re.search(r"typedef struct %s_s \{(.*?)\} %s_t;" % (struct, struct), h, re.S)
    body = m.group(1)
    fields = []
    for line in body.split(";"):
        line = re.sub(r"/\*.*?\*/", "", line).strip()
        mm = re.match(r".*?\s\**(\w+)\s*((?:\[\d+\])*)$", line)
        if mm:
            fields.append(mm.group(1))
    pre = h[:h.index("typedef struct %s_s" % struct)]
    src = "#include <stdio.h>\n#include <stddef.h>\n" + pre[pre.index("typedef struct rvcn_dec_message_index_s"):] if "rvcn_dec_message_index_s" in pre else ""
    src = "#include <stdio.h>\n#include <stddef.h>\n#include <stdint.h>\n#include <stdbool.h>\n" + re.sub(r"#include.*", "", h)
    src += "\nint main(){\n"
    for f in fields:
        src += f' printf("%zu %zu {f}\\n", offsetof({struct}_t,{f}), sizeof((({struct}_t*)0)->{f}));\n'
    src += f' printf("%zu %zu __size\\n", sizeof({struct}_t), sizeof({struct}_t));\n}}\n'
    d = tempfile.mkdtemp()
    open(d + "/x.c", "w").write(src)
    subprocess.run(["clang", "-w", d + "/x.c", "-o", d + "/x"], check=True)
    out = subprocess.run([d + "/x"], capture_output=True, text=True).stdout
    return [(int(a), int(b), n) for a, b, n in (l.split() for l in out.splitlines())]

def u32(b, o): return int.from_bytes(b[o:o + 4], "little")

def show(b, base, struct, filt=None):
    for off, size, name in layout(struct):
        if name == "__size":
            continue
        if filt and not re.search(filt, name):
            continue
        raw = b[base + off: base + off + size]
        if size in (1, 2, 4) and len(raw) == size:
            v = int.from_bytes(raw, "little", signed=False)
            print(f"  {off:5d} {name:34s} {v} (0x{v:x})")
        else:
            nz = [i for i, x in enumerate(raw) if x]
            print(f"  {off:5d} {name:34s} [{size}B] nonzero_bytes={len(nz)} first={raw[:24].hex()}")

b = open(sys.argv[1], "rb").read()
filt = sys.argv[2] if len(sys.argv) > 2 else None
hs, total, nbuf, mtype, handle, fb = (u32(b, i * 4) for i in range(6))
print(f"header: header_size={hs} total_size={total} num_buffers={nbuf} msg_type={mtype} stream_handle=0x{handle:x} fb={fb}")
names = {2: "rvcn_dec_message_decode", 17: "rvcn_dec_message_av1", 14: "rvcn_dec_message_vp9", 3: "rvcn_dec_message_drm"}
for i in range(nbuf):
    mid, off, size, filled = (u32(b, 24 + 16 * i + 4 * k) for k in range(4))
    print(f"index[{i}]: id={mid} offset={off} size={size} filled={filled}")
    if mid in names:
        print(f"== {names[mid]} @ {off}")
        show(b, off, names[mid], filt)
