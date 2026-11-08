// Hardware AV1 decoder for AMD VCN on macOS, driven through Apple's AMDRadeonVADriver2.
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stdint.h>
#include "av1parse.h"

typedef struct VcnAV1 VcnAV1;

// Called for every frame that must be displayed (in display order, as the bitstream dictates).
// The pixel buffer is only guaranteed during the call: retain it to keep it.
typedef void (*VcnAV1OutputFn)(void *ctx, CVPixelBufferRef frame, const AV1Parser *p, int64_t userTag);

VcnAV1 *vcnav1_create(uint32_t maxWidth, uint32_t maxHeight, char *err, size_t errLen);
void vcnav1_destroy(VcnAV1 *d);
// Feed configuration OBUs (sequence header) e.g. from av1C.
int vcnav1_configure(VcnAV1 *d, const uint8_t *obus, size_t size);
// Decode one temporal unit. Output frames are reported through fn (synchronously).
int vcnav1_decode(VcnAV1 *d, const uint8_t *tu, size_t size, int64_t userTag, VcnAV1OutputFn fn, void *ctx);
// Drop all reference state (e.g. after a seek)
void vcnav1_flush(VcnAV1 *d);
const char *vcnav1_last_error(VcnAV1 *d);
// Attributes of the pixel buffers the decoder outputs (caller releases).
CFDictionaryRef vcnav1_copy_pixel_buffer_attributes(uint32_t w, uint32_t h, bool tenBit);
extern int vcnav1_debug;
// Set by the VideoToolbox plugin (no environment there); command-line tools use VCNAV1_ALLOW_GPU.
extern int vcnav1_gpu_armed;
