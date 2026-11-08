# Make synthetic AV1 IVF clips with SVT-AV1 and per-frame I420 MD5 references decoded by dav1d.
#   .re/venv/bin/python tools/mk4k.py <out.ivf> <w> <h> <frames> <bitdepth 8|10> [svt-params]
import hashlib, sys
import av, numpy as np

out, W, H, N, BD = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
params = sys.argv[6] if len(sys.argv) > 6 else ""

def frame(i):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    rng = np.random.default_rng(1234)
    tex = rng.integers(0, 255, (256, 256)).astype(np.float32)
    t = np.roll(np.roll(tex, i * 7, 0), i * 13, 1)
    t = np.tile(t, (H // 256 + 1, W // 256 + 1))[:H, :W]
    y = 0.35 * (xx / W * 255) + 0.35 * t + 0.3 * (128 + 127 * np.sin((xx + i * 24) / 90) * np.cos((yy - i * 11) / 70))
    for k in range(6):  # moving discs
        cx, cy = (W * (0.1 + 0.15 * k) + i * (9 + 3 * k)) % W, H * (0.2 + 0.1 * k) + 120 * np.sin(i / 9 + k)
        y = np.where((xx - cx) ** 2 + (yy - cy) ** 2 < (60 + 20 * k) ** 2, 235 - 20 * k, y)
    u = 128 + 60 * np.sin((xx[::2, ::2] + i * 5) / 200)
    v = 128 + 60 * np.cos((yy[::2, ::2] - i * 4) / 150)
    return y, u, v

import os
if not os.environ.get("MD5ONLY"):
    oc = av.open(out, "w", format="ivf")
    st = oc.add_stream("libsvtav1", rate=30)
    st.width, st.height = W, H
    st.pix_fmt = "yuv420p10le" if BD == 10 else "yuv420p"
    st.options = {"preset": "10", "crf": "32", "g": "30"}
    if params:
        st.options["svtav1-params"] = params
    for i in range(N):
        y, u, v = frame(i)
        if BD == 10:
            planes = [(p * 4).clip(0, 1023).astype(np.uint16) for p in (y, u, v)]
            f = av.VideoFrame(W, H, "yuv420p10le")
        else:
            planes = [p.clip(0, 255).astype(np.uint8) for p in (y, u, v)]
            f = av.VideoFrame(W, H, "yuv420p")
        for k, p in enumerate(planes):
            buf = np.frombuffer(f.planes[k], dtype=p.dtype).reshape(-1, f.planes[k].line_size // p.itemsize)
            buf[: p.shape[0], : p.shape[1]] = p
        f.pts = i
        for pkt in st.encode(f):
            oc.mux(pkt)
    for pkt in st.encode():
        oc.mux(pkt)
    oc.close()

# reference MD5s via dav1d
ic = av.open(out)
ic.streams.video[0].codec_context.options = {}
dec = av.codec.CodecContext.create("libdav1d", "r")
n = 0
def emit(fp, fr):
    global n
    m = hashlib.md5()
    bpe = 2 if BD == 10 else 1
    for k, (pw, ph) in enumerate([(W, H), ((W + 1) // 2, (H + 1) // 2), ((W + 1) // 2, (H + 1) // 2)]):
        pl = fr.planes[k]
        a = np.frombuffer(pl, dtype=np.uint8).reshape(-1, pl.line_size)[:ph, : pw * bpe]
        m.update(a.tobytes())
    fp.write(f"{m.hexdigest()}  frame-{n:04d}.i420\n")
    n += 1
with open(out + ".md5", "w") as fp:
    for pkt in ic.demux(video=0):
        if pkt.size:
            for fr in dec.decode(pkt):
                emit(fp, fr)
    for fr in dec.decode(None):
        emit(fp, fr)
print(out, "frames md5:", n)
