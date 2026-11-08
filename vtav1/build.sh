#!/bin/zsh
# Build AV1VCNDecoder.bundle (VideoToolbox decoder plugin for av01 on AMD VCN).
set -e
cd "${0:A:h}"
B=build/AV1VCNDecoder.bundle
rm -rf $B
mkdir -p $B/Contents/MacOS
cp Info.plist $B/Contents/Info.plist
clang -arch x86_64 -O2 -g -bundle -fvisibility=hidden -Wall -Wno-unused-function -Wno-four-char-constants \
  -Wno-deprecated-declarations -mmacosx-version-min=13.0 \
  AV1VCNDecoder.c ../vcnav1/vcnav1.c ../vcnav1/av1parse.c \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox \
  -framework IOKit -framework IOSurface \
  -o $B/Contents/MacOS/AV1VCNDecoder
codesign -f -s - $B
nm -gU $B/Contents/MacOS/AV1VCNDecoder | grep -i createinstance
echo "built $B"
