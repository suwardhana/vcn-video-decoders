#!/bin/zsh
# Build "AMD VCN Video Decoders.app": SwiftUI front-end + engine.sh + both decoder bundles.
# Output: installer/build/AMD VCN Video Decoders.app  (make-dmg.sh packages it for sharing).
set -e
cd "${0:A:h}"
APP="build/AMD VCN Video Decoders.app"
AV1_SRC=../vtav1/build/AV1VCNDecoder.bundle
VP9_SRC=../vtvp9/build/VP9VCNDecoder.bundle
[[ -d $AV1_SRC && -d $VP9_SRC ]] || { echo "build vtav1 and vtvp9 first"; exit 1; }

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# x86_64 only: the decoders drive the AMD VCN, which only exists on Intel/AMD hackintoshes.
xcrun swiftc -parse-as-library -O \
  -target x86_64-apple-macos15.0 \
  app/main.swift -o "$APP/Contents/MacOS/VCNInstaller"

cp app/Info.plist "$APP/Contents/Info.plist"
cp engine.sh validated-builds.json "$APP/Contents/Resources/"
[[ -f assets/AppIcon.icns ]] || zsh make-assets.sh
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/Resources/engine.sh"
ditto "$AV1_SRC" "$APP/Contents/Resources/AV1VCNDecoder.bundle"
ditto "$VP9_SRC" "$APP/Contents/Resources/VP9VCNDecoder.bundle"
rm -rf "$APP"/Contents/Resources/*.bundle/Contents/MacOS/*.dSYM

codesign -f -s - "$APP"
rm -f build/VCN-Video-Decoders.zip
echo "built $APP"
