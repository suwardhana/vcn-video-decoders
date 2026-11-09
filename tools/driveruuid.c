// Print the LC_UUID of the loaded AMDRadeonVADriver2 image (identifies the
// exact driver build).
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  const char* path =
      "/System/Library/Extensions/AMDRadeonVADriver2.bundle/Contents/MacOS/"
      "AMDRadeonVADriver2";
  if (!dlopen(path, RTLD_NOW | RTLD_LOCAL)) {
    printf("dlopen failed: %s\n", dlerror());
    return 1;
  }
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    if (!strstr(_dyld_get_image_name(i), "AMDRadeonVADriver2")) continue;
    const struct mach_header_64* h = (const void*)_dyld_get_image_header(i);
    const struct load_command* lc = (const void*)(h + 1);
    for (uint32_t k = 0; k < h->ncmds;
         k++, lc = (const void*)((const char*)lc + lc->cmdsize))
      if (lc->cmd == LC_UUID) {
        const uint8_t* u = ((const struct uuid_command*)lc)->uuid;
        for (int j = 0; j < 16; j++) printf("%02X", u[j]);
        printf("\n");
      }
  }
  return 0;
}
