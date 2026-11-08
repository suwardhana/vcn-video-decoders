//
//  kern_amfi.cpp — see kern_amfi.hpp.
//
#include "kern_amfi.hpp"
#include "cdhashes.h"
#include <Headers/kern_api.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>

// AMFI's cdHash() returns a 20-byte (sha256-truncated) cdhash — confirmed in
// library_validation(): memcmp(..., 0x14u) and cdhash_to_string() iterates 20 times. Our
// cdhashes.h stores the full 32-byte sha256 cdhash; the AMFI 20-byte cdhash is exactly its
// first 20 bytes, so we compare that prefix.
static constexpr size_t kAmfiCdhashLen = 20;

// AppleMobileFileIntegrity. Symbols confirmed present and identically named in the kernelcaches
// for 15.8.2 (24H232), 26.7.1 (25G241) and 26.7.2 (25G332), so Lilu resolves them by symbol on
// all three — no per-version byte patterns needed.
static const char *kAMFIPaths[] {
	"/System/Library/Extensions/AppleMobileFileIntegrity.kext/Contents/MacOS/AppleMobileFileIntegrity"
};
static KernelPatcher::KextInfo kextAMFI {
	"com.apple.driver.AppleMobileFileIntegrity",
	kAMFIPaths, arrsize(kAMFIPaths),
	{true},  // sys[Loaded] = true: AMFI is already loaded (boot KC) when our patcher runs
	{},
	KernelPatcher::KextInfo::Unloaded
};

// static int _library_validation_failure(ProcessAccessor&, FileGlobAccessor&, SystemFacts&,
//                                        bool, const char*, unsigned long long, unsigned long)
// Returns 1 on override (library allowed), 0 on rejection. All args are register-width
// (pointers / promoted scalars), so we pass them straight through as uint64_t to preserve the ABI.
using t_lvf = int (*)(void *proc, void *fg, void *facts, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7);
static t_lvf org_lvf {nullptr};

// const uint8_t *AbstractCSBlobAccessor::cdHash(this); returns ptr to 20 bytes, or null.
// FileGlobAccessor has AbstractCSBlobAccessor as its base at offset 0, so the FileGlobAccessor*
// we receive can be passed directly as `this`.
using t_cdHash = const uint8_t * (*)(void *csBlobAccessor);
static t_cdHash fn_cdHash {nullptr};

static int vcn_library_validation_failure(void *proc, void *fg, void *facts,
                                          uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {
	if (fn_cdHash && fg) {
		const uint8_t *h = fn_cdHash(fg);
		if (h) {
			for (size_t i = 0; i < kAllowedCdhashCount; i++) {
				if (memcmp(h, kAllowedCdhashes[i], kAmfiCdhashLen) == 0) {
					DBGLOG("amfi", "overriding library validation for allow-listed VCN plugin #%zu", i);
					return 1;  // == AMFI's own "Library Validation overridden" result
				}
			}
		}
	}
	return org_lvf(proc, fg, facts, a4, a5, a6, a7);
}

static void onAMFILoad(void *, KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
	if (kextAMFI.loadIndex != index)
		return;

	fn_cdHash = patcher.solveSymbol<t_cdHash>(index, "__ZN22AbstractCSBlobAccessor6cdHashEv", address, size);
	if (!fn_cdHash) {
		SYSLOG("amfi", "could not solve AbstractCSBlobAccessor::cdHash — AMFI override disabled");
		patcher.clearError();
		return;
	}

	KernelPatcher::RouteRequest req {
		"__ZL27_library_validation_failureR15ProcessAccessorR16FileGlobAccessorR11SystemFactsbPKcym",
		vcn_library_validation_failure,
		org_lvf
	};
	if (patcher.routeMultiple(index, &req, 1, address, size))
		SYSLOG("amfi", "routed _library_validation_failure (scoped AMFI override active)");
	else {
		SYSLOG("amfi", "failed to route _library_validation_failure (%d)", patcher.getError());
		patcher.clearError();
	}
}

void AmfiBypass::init() {
	SYSLOG("amfi", "init: requesting AMFI kext route");
	lilu.onKextLoadForce(&kextAMFI, 1, onAMFILoad, nullptr);
}
