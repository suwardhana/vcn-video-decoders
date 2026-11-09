// Print C strings (and CFString literals' backing C strings) from loaded
// dyld-cache images that contain a substring.
//   imgstrings <substring> <image-substring>...
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  dlopen("/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox",
         RTLD_NOW);
  dlopen("/System/Library/Frameworks/MediaToolbox.framework/MediaToolbox",
         RTLD_NOW);
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char* name = _dyld_get_image_name(i);
    int want = 0;
    for (int a = 2; a < argc; a++)
      if (strstr(name, argv[a])) want = 1;
    if (!want) continue;
    const struct mach_header_64* h = (const void*)_dyld_get_image_header(i);
    unsigned long size = 0;
    const char* sects[] = {"__cstring", "__oslogstring", "__const"};
    for (int s = 0; s < 3; s++) {
      const char* p = (const char*)getsectiondata(h, "__TEXT", sects[s], &size);
      if (!p) continue;
      for (const char* q = p; q < p + size; q += strlen(q) + 1)
        if (strstr(q, argv[1]))
          printf("%s [%s]: %s\n", strrchr(name, '/') + 1, sects[s], q);
    }
  }
  return 0;
}
