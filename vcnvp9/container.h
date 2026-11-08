// Minimal IVF and WebM readers for the test tools: one chunk per container frame, video track only, no lacing.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  uint8_t *data;
  size_t size, pos;
  bool ivf;
  // WebM walk: end of the cluster being read
  size_t cluster_end;
  // First video track from Tracks; 0 until it is seen.
  uint64_t video_track;
} Container;

static inline bool container_open(Container *c, const char *path) {
  memset(c, 0, sizeof(*c));
  FILE *fp = fopen(path, "rb");
  if (!fp) return false;
  fseek(fp, 0, SEEK_END);
  long n = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  c->data = malloc((size_t)n);
  c->size = fread(c->data, 1, (size_t)n, fp);
  fclose(fp);
  if (c->size >= 32 && !memcmp(c->data, "DKIF", 4)) {
    c->ivf = true;
    c->pos = (size_t)(c->data[6] | c->data[7] << 8);
  }
  return true;
}

static inline void container_close(Container *c) { free(c->data); }

static inline bool ebml_id(Container *c, uint32_t *id) {
  if (c->pos >= c->size) return false;
  uint8_t b = c->data[c->pos];
  int len = b & 0x80 ? 1 : b & 0x40 ? 2 : b & 0x20 ? 3 : b & 0x10 ? 4 : 0;
  if (!len || c->pos + (size_t)len > c->size) return false;
  uint32_t v = 0;
  for (int i = 0; i < len; i++) v = v << 8 | c->data[c->pos++];
  *id = v;
  return true;
}

// Returns false on a malformed size. *unknown is set for an unknown-size master element.
static inline bool ebml_size(Container *c, uint64_t *out, bool *unknown) {
  if (c->pos >= c->size) return false;
  uint8_t b = c->data[c->pos];
  int len = 0;
  for (int i = 0; i < 8; i++)
    if (b & (0x80 >> i)) { len = i + 1; break; }
  if (!len || c->pos + (size_t)len > c->size) return false;
  uint64_t v = (uint64_t)(b & (0xff >> len));
  bool all = v == (uint64_t)(0xff >> len);
  c->pos++;
  for (int i = 1; i < len; i++) {
    all = all && c->data[c->pos] == 0xff;
    v = v << 8 | c->data[c->pos++];
  }
  *out = v;
  if (unknown) *unknown = all;
  return true;
}

// Finds the first video track inside a Tracks element. Leaves the position where it found it.
static inline void webm_read_tracks(Container *c, size_t end) {
  size_t saved = c->pos;
  while (c->pos < end && !c->video_track) {
    uint32_t id;
    uint64_t sz;
    if (!ebml_id(c, &id) || !ebml_size(c, &sz, NULL)) break;
    if (c->pos + sz > end) break;
    if (id == 0xAE) {  // TrackEntry
      size_t entry_end = c->pos + (size_t)sz;
      uint64_t number = 0, type = 0;
      while (c->pos < entry_end) {
        uint32_t eid;
        uint64_t esz;
        if (!ebml_id(c, &eid) || !ebml_size(c, &esz, NULL) || c->pos + esz > entry_end) break;
        if ((eid == 0xD7 || eid == 0x83) && esz <= 8) {
          uint64_t v = 0;
          for (uint64_t i = 0; i < esz; i++) v = v << 8 | c->data[c->pos + i];
          if (eid == 0xD7) number = v; else type = v;
        }
        c->pos += (size_t)esz;
      }
      if (type == 1) c->video_track = number;
      c->pos = entry_end;
    } else {
      c->pos += (size_t)sz;
    }
  }
  c->pos = saved;
}

// Next frame of the file, pointing into the file's memory. Returns false at the end.
static inline bool container_next(Container *c, const uint8_t **out, size_t *size) {
  if (c->ivf) {
    if (c->pos + 12 > c->size) return false;
    const uint8_t *h = c->data + c->pos;
    size_t s = (size_t)h[0] | (size_t)h[1] << 8 | (size_t)h[2] << 16 | (size_t)h[3] << 24;
    c->pos += 12;
    if (c->pos + s > c->size) return false;
    *out = c->data + c->pos;
    *size = s;
    c->pos += s;
    return true;
  }
  for (;;) {
    uint32_t id;
    uint64_t sz;
    bool unknown = false;
    if (!ebml_id(c, &id) || !ebml_size(c, &sz, &unknown)) return false;
    if (id == 0x18538067 || id == 0x1F43B675 || id == 0xA0) continue;  // Segment, Cluster, BlockGroup: descend
    if (unknown) return false;
    if (c->pos + sz > c->size) return false;
    if (id == 0x1654AE6B) webm_read_tracks(c, c->pos + (size_t)sz);
    if (id == 0xA3 || id == 0xA1) {  // SimpleBlock, Block
      size_t start = c->pos;
      uint64_t track;
      if (!ebml_size(c, &track, NULL)) return false;
      size_t head = c->pos - start + 3;  // track number, timecode, flags
      if (head > sz) return false;
      c->pos = start + (size_t)sz;
      if (c->video_track && track != c->video_track) continue;
      *out = c->data + start + head;
      *size = (size_t)sz - head;
      return true;
    }
    c->pos += (size_t)sz;
  }
}
