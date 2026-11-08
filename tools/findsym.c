// Look for symbols across a list of system libraries: findsym <symbol>...
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
  const char *libs[] = {
      "/System/Library/PrivateFrameworks/MobileSoftwareUpdate.framework/MobileSoftwareUpdate",
      "/System/Library/PrivateFrameworks/MSUDataAccessor.framework/MSUDataAccessor",
      "/System/Library/PrivateFrameworks/MiniSoftwareUpdate.framework/MiniSoftwareUpdate",
      "/System/Library/PrivateFrameworks/SoftwareUpdateCore.framework/SoftwareUpdateCore",
      "/System/Library/PrivateFrameworks/AppleArchive.framework/AppleArchive",
      "/usr/lib/libParallelCompression.dylib", "/usr/lib/libAppleArchive.dylib", "/usr/lib/libcompression.dylib",
      "/usr/lib/libbsdiff.dylib", "/usr/lib/libRawImagePatch.dylib", 0};
  for (int i = 0; libs[i]; i++) {
    void *h = dlopen(libs[i], RTLD_NOW | RTLD_LOCAL);
    printf("%-90s %s\n", libs[i], h ? "loaded" : "-");
    if (!h) continue;
    for (int a = 1; a < argc; a++) {
      void *s = dlsym(h, argv[a]);
      if (s) printf("   %s = %p\n", argv[a], s);
    }
  }
  return 0;
}
