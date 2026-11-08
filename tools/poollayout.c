// Compare the IOSurface layout a CVPixelBufferPool produces against the layout vcnav1 already
// validated on the VCN (pitch aligned 256, height aligned 64, UV plane offset aligned 4096).
#include <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurface.h>
#include <stdio.h>

static CFNumberRef num(long long v) { return CFNumberCreate(NULL, kCFNumberLongLongType, &v); }

static void test(int w, int h, OSType fmt) {
  int ten = fmt == 'x420';
  long pitch = ((w * (ten ? 2 : 1)) + 255) & ~255L, ah = (h + 63) & ~63L;
  long uvOff = (pitch * ah + 4095) & ~4095L;
  CFMutableDictionaryRef a = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef io = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(a, kCVPixelBufferPixelFormatTypeKey, num(fmt));
  CFDictionarySetValue(a, kCVPixelBufferWidthKey, num(w));
  CFDictionarySetValue(a, kCVPixelBufferHeightKey, num(h));
  CFDictionarySetValue(a, kCVPixelBufferBytesPerRowAlignmentKey, num(256));
  CFDictionarySetValue(a, kCVPixelBufferPlaneAlignmentKey, num(4096));
  CFDictionarySetValue(a, kCVPixelBufferExtendedPixelsBottomKey, num(ah - h));
  CFDictionarySetValue(a, kCVPixelBufferIOSurfacePropertiesKey, io);
  CVPixelBufferPoolRef pool = NULL;
  CVReturn r = CVPixelBufferPoolCreate(NULL, NULL, a, &pool);
  CVPixelBufferRef pb = NULL;
  if (!r) r = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pb);
  if (r) { printf("%dx%d %.4s: error %d\n", w, h, (char *)&fmt, r); return; }
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  uint8_t *b0 = IOSurfaceGetBaseAddressOfPlane(s, 0), *b1 = IOSurfaceGetBaseAddressOfPlane(s, 1);
  long gotPitch = IOSurfaceGetBytesPerRowOfPlane(s, 0), gotUV = b1 - b0, gotUVp = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  printf("%4dx%-4d %c%c%c%c pool: pitch %ld uvPitch %ld uvOff %ld alloc %zu | want pitch %ld uvOff %ld => %s\n", w, h,
         fmt >> 24, fmt >> 16, fmt >> 8, fmt, gotPitch, gotUVp, gotUV, IOSurfaceGetAllocSize(s), pitch, uvOff,
         gotPitch == pitch && gotUVp == pitch && gotUV == uvOff ? "MATCH" : "DIFF");
  CVPixelBufferRelease(pb);
  CVPixelBufferPoolRelease(pool);
}

int main(void) {
  int sz[][2] = {{16, 16}, {66, 66}, {352, 288}, {640, 360}, {1920, 1080}, {2560, 1440}, {3840, 2160}, {3840, 1608}};
  for (int i = 0; i < 8; i++) { test(sz[i][0], sz[i][1], '420v'); test(sz[i][0], sz[i][1], 'x420'); }
  return 0;
}
