//
//  kern_coremedia.hpp — CoreMedia /Library codesign bypass for the media
//  processes.
//
//  Problem: CoreMedia's figRegistry scans /Library/Video/Plug-Ins with a
//  code-signature requirement (SecStaticCode vs
//  kFigRegistryAppleCodeSignRequirement). Our adhoc plugins fail it, so today
//  they must live in /System/Library/Video/Plug-Ins (scanned with no check),
//  which needs the sealed-volume root patch. This neutralises that check — in
//  userspace, only inside com.apple.WebKit.GPU and VTDecoderXPCService — so the
//  bundles can load from /Library with no root patch. AMFI (mapping adhoc code
//  into those platform processes) is handled separately by AMFIPass.kext,
//  already standard on OpenCore.
//

#ifndef VCNVTKEXT_KERN_COREMEDIA_HPP_
#define VCNVTKEXT_KERN_COREMEDIA_HPP_

#include <Headers/kern_user.hpp>

namespace CoreMediaBypass {
// Register the UserPatcher proc + binary mods. Called from the plugin's
// onPatcherLoad.
void init();
}  // namespace CoreMediaBypass

#endif  // VCNVTKEXT_KERN_COREMEDIA_HPP_
