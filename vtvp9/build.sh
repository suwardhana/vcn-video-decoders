#!/bin/zsh
# Builds VP9VCNDecoder.bundle and vtvp9test. Installs nothing.
set -e
cd "${0:A:h}"
B=build/VP9VCNDecoder.bundle
rm -rf $B
mkdir -p $B/Contents/MacOS
cp Info.plist $B/Contents/Info.plist
clang -arch x86_64 -O2 -g -bundle -fvisibility=hidden -Wall -Wno-unused-function -Wno-four-char-constants \
  -Wno-deprecated-declarations -mmacosx-version-min=13.0 \
  VP9VCNDecoder.c ../vcnvp9/vcnvp9.c ../vcnvp9/vp9parse.c \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox \
  -framework IOKit -framework IOSurface \
  -o $B/Contents/MacOS/VP9VCNDecoder
codesign -f -s - $B
nm -gU $B/Contents/MacOS/VP9VCNDecoder | grep -i createinstance
clang -arch x86_64 -O1 -g -Wall -Wno-four-char-constants -Wno-deprecated-declarations -mmacosx-version-min=13.0 \
  vtvp9test.c ../vcnvp9/vp9parse.c \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox \
  -o vtvp9test
echo "built $B and vtvp9test"
