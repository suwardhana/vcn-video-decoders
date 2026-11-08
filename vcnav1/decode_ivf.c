// Decode an AV1 IVF file on the VCN and print per-frame I420 MD5 (libaom test-vector format),
// optionally comparing against an .md5 file.
// usage: decode_ivf file.ivf [expected.md5] [-v] [-o out.yuv]
#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include "vcnav1.h"

typedef struct {
  int frames, mismatches;
  FILE *md5, *out;
  const char *name;
  int nohash;
  double cb_ms;
} Ctx;

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static void on_output(void *vctx, CVPixelBufferRef pb, const AV1Parser *p, int64_t tag) {
  Ctx *c = vctx;
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  double t0 = now_ms();
  if (c->nohash) { c->frames++; c->cb_ms += now_ms() - t0; return; }
  IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
  int w = p->fh.UpscaledWidth, h = p->fh.FrameHeight;
  if (p->fh.show_existing_frame) {
    const AV1RefSlot *r = &p->ref[p->fh.frame_to_show_map_idx];
    w = r->upscaled_width; h = r->frame_height;
  }
  bool ten = IOSurfaceGetPixelFormat(s) == 'x420';
  int bpe = ten ? 2 : 1;
  uint8_t *y = IOSurfaceGetBaseAddressOfPlane(s, 0), *uv = IOSurfaceGetBaseAddressOfPlane(s, 1);
  size_t ys = IOSurfaceGetBytesPerRowOfPlane(s, 0), uvs = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  CC_MD5_CTX m;
  CC_MD5_Init(&m);
  int cw = (w + 1) / 2, ch = (h + 1) / 2;
  uint8_t *row = malloc((size_t)w * 2 + 16);
  for (int r = 0; r < h; r++) {
    if (ten) {  // P010 -> little-endian 16-bit samples (value in low 10 bits)
      uint16_t *src = (uint16_t *)(y + r * ys), *dst = (uint16_t *)row;
      for (int i = 0; i < w; i++) dst[i] = src[i] >> 6;
      CC_MD5_Update(&m, row, w * 2);
      if (c->out) fwrite(row, 2, w, c->out);
    } else {
      CC_MD5_Update(&m, y + r * ys, w);
      if (c->out) fwrite(y + r * ys, 1, w, c->out);
    }
  }
  for (int pl = 0; pl < 2; pl++) {
    for (int r = 0; r < ch; r++) {
      if (ten) {
        uint16_t *src = (uint16_t *)(uv + r * uvs), *dst = (uint16_t *)row;
        for (int i = 0; i < cw; i++) dst[i] = src[2 * i + pl] >> 6;
      } else {
        for (int i = 0; i < cw; i++) row[i] = uv[r * uvs + 2 * i + pl];
      }
      CC_MD5_Update(&m, row, cw * bpe);
      if (c->out) fwrite(row, bpe, cw, c->out);
    }
  }
  free(row);
  IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
  uint8_t dg[16];
  CC_MD5_Final(dg, &m);
  char hex[33];
  for (int i = 0; i < 16; i++) sprintf(hex + 2 * i, "%02x", dg[i]);
  c->frames++;
  char expect[64] = "";
  if (c->md5) {
    char line[512];
    if (fgets(line, sizeof(line), c->md5)) sscanf(line, "%32s", expect);
  }
  bool ok = !c->md5 || !strcmp(expect, hex);
  if (!ok) c->mismatches++;
  printf("frame %3d %dx%d %s%s%s\n", c->frames, w, h, hex, c->md5 ? (ok ? "  OK" : "  MISMATCH expected ") : "", ok ? "" : expect);
  c->cb_ms += now_ms() - t0;
}

int main(int argc, char **argv) {
  const char *path = NULL, *md5 = NULL, *outp = NULL;
  int nohash = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-v")) vcnav1_debug = 1;
    else if (!strcmp(argv[i], "-o")) outp = argv[++i];
    else if (!strcmp(argv[i], "-n")) nohash = 1;
    else if (!path) path = argv[i];
    else md5 = argv[i];
  }
  FILE *fp = fopen(path, "rb");
  if (!fp) { perror(path); return 1; }
  uint8_t hdr[32];
  if (fread(hdr, 1, 32, fp) != 32 || memcmp(hdr, "DKIF", 4)) { fprintf(stderr, "not IVF\n"); return 1; }
  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  char err[256];
  VcnAV1 *d = vcnav1_create(w > 0 ? (w < 4096 ? 4096 : w) : 4096, h > 0 ? (h < 2304 ? 2304 : h) : 2304, err, sizeof(err));
  if (!d) { fprintf(stderr, "create: %s\n", err); return 1; }
  Ctx c = {.md5 = md5 ? fopen(md5, "r") : NULL, .out = outp ? fopen(outp, "wb") : NULL, .name = path, .nohash = nohash};
  double t_start = 0, worst = 0;
  uint8_t fh[12];
  int n = 0;
  while (fread(fh, 1, 12, fp) == 12) {
    uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
    uint8_t *buf = malloc(sz);
    if (fread(buf, 1, sz, fp) != sz) { free(buf); break; }
    double cb0 = c.cb_ms, t0 = now_ms();
    if (!t_start) t_start = t0;
    int rc = vcnav1_decode(d, buf, sz, n++, on_output, &c);
    double dt = now_ms() - t0 - (c.cb_ms - cb0);
    if (getenv("TU_TIMES")) fprintf(stderr, "tu %d %u bytes %.2f ms\n", n - 1, sz, dt);
    if (n > 1 && dt > worst) worst = dt;
    if (rc) { fprintf(stderr, "decode error at TU %d: %s\n", n - 1, vcnav1_last_error(d)); free(buf); break; }
    free(buf);
  }
  double total = now_ms() - t_start, dec = total - c.cb_ms;
  printf("%s: %d frames, %d mismatches\n", path, c.frames, c.mismatches);
  printf("timing: %.1f ms decode-only (%.1f fps), worst TU %.2f ms, %.1f ms in output callback\n", dec, c.frames * 1000.0 / dec, worst, c.cb_ms);
  vcnav1_destroy(d);
  return c.mismatches ? 2 : 0;
}
