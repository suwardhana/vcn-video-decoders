// Dump constants from the loaded AMD VA driver at IDA (unslid) addresses.
// usage: dumpconst <ida_addr_hex> <bytes> [...]
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "avd.h"
#define IDA_AVD_CREATE 0x7ffb10afe9e0ull
int main(int argc, char** argv) {
  void* lib = dlopen(AVD_DRIVER_PATH, RTLD_NOW);
  uintptr_t live = (uintptr_t)dlsym(lib, "AVD_CreateAVDAccelerator");
  intptr_t slide = (intptr_t)live - (intptr_t)IDA_AVD_CREATE;
  for (int i = 1; i + 1 < argc; i += 2) {
    uint64_t a = strtoull(argv[i], NULL, 16);
    int n = atoi(argv[i + 1]);
    uint8_t* p = (uint8_t*)(a + slide);
    printf("%s:", argv[i]);
    for (int k = 0; k < n; k++) printf(" %02x", p[k]);
    printf("\n");
  }
}
