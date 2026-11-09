// Apply a RIDIFF10 image patch (e.g.
// payloadv2/image_patches/cryptex-system-x86_64) with no source image,
// producing the full disk image, using libParallelCompression's RawImagePatch.
//   rawpatch <patch> <out.dmg>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  const char* input;   // +0x00 source image (NULL: patch from nothing)
  const void* unk08;   // +0x08
  const char* unk10;   // +0x10 defaults to +0x18
  const char* output;  // +0x18
  const char* patch;   // +0x20
  int verbose;         // +0x28
  int threads;         // +0x2c 0 = default
  char pad[64];
} RawImagePatchArgs;

int main(int argc, char** argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: rawpatch <patch> <out>\n");
    return 1;
  }
  void* h = dlopen("/usr/lib/libParallelCompression.dylib", RTLD_NOW);
  int (*fn)(RawImagePatchArgs*) = h ? dlsym(h, "RawImagePatch") : NULL;
  if (!fn) {
    fprintf(stderr, "RawImagePatch not found: %s\n", dlerror());
    return 1;
  }
  RawImagePatchArgs a;
  memset(&a, 0, sizeof(a));
  a.patch = argv[1];
  a.output = argv[2];
  a.verbose = 3;
  int r = fn(&a);
  perror("errno");
  printf("RawImagePatch -> %d\n", r);
  return r != 0;
}
