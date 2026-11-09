// Print which private VideoToolbox decoder-plugin symbols exist on this macOS.
#include <dlfcn.h>
#include <stdio.h>
int main(void) {
  void* h =
      dlopen("/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox",
             RTLD_NOW);
  const char* s[] = {"VTRegisterVideoDecoderWithInfo",
                     "VTRegisterVideoDecoder",
                     "VTDecoderSessionEmitDecodedFrame",
                     "VTDecoderSessionGetPixelBufferPool",
                     "VTDecoderSessionSetPixelBufferAttributes",
                     "VTVideoDecoderGetClassID",
                     "VTVideoDecoderGetCMBaseObject",
                     "VTRegisterSupplementalVideoDecoderIfAvailable",
                     "VTIsHardwareDecodeSupported",
                     "VTDecoderSessionCreateVideoFormatDescription",
                     0};
  for (int i = 0; s[i]; i++) printf("%-48s %p\n", s[i], dlsym(h, s[i]));
  return 0;
}
