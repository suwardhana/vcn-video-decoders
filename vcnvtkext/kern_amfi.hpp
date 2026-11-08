//
//  kern_amfi.hpp — scoped AMFI library-validation override for the VCN plugins.
//
//  Makes the AMD VCN AV1/VP9 VideoToolbox plugins (adhoc-signed, no Team ID, not platform
//  binaries) pass AMFI's library-validation check WITHOUT disabling validation globally. It
//  routes AppleMobileFileIntegrity's internal `_library_validation_failure` and, only when the
//  library being mapped has one of our two allow-listed cdhashes, returns 1 — the exact value
//  AMFI itself returns on its "Library Validation overridden" path. Everything else falls
//  through to the original, untouched.
//
//  This is what lets the kext work WITHOUT AMFIPass. If AMFIPass (or amfi_get_out_of_my_way) is
//  present, the adhoc library never reaches the failure path, so this hook simply never fires —
//  it is harmless and redundant in that case.
//
#ifndef kern_amfi_hpp
#define kern_amfi_hpp

namespace AmfiBypass {
	void init();
}

#endif /* kern_amfi_hpp */
