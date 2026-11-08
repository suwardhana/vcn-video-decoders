//
//  kern_start.cpp - VCNVideoProfile, a Lilu plugin.
//
//  macOS keeps Navi 21 on the COMPUTE workload profile because the framebuffer's Info.plist sets
//  PP_WorkLoadPolicyMask=16 and copies it over the GPU's registry entry at start, so a device
//  property cannot change it. Linux runs VCN under the VIDEO profile instead. This plugin answers
//  that one registry read with another mask and logs what actually reaches the firmware.
//
//  Boot args: -vcnvpoff disables it, vcnwlmask=N picks the mask (default 4, VIDEO; valid 1..127).
//  Bits, per Phw_SwSmu_WorkLoadPolicyManager's log strings: 1 FULLSCREEN3D, 2 POWERSAVING, 4 VIDEO,
//  8 VR, 0x10 COMPUTE, 0x20 CUSTOM, 0x40 W3D.
//
#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>

static constexpr uint32_t kDefaultMask = 4;
static constexpr uint32_t kMaxMask = 0x7F;
static constexpr int kValidatedKernelMinor = 6;  // Darwin 25.6, the build these signatures were read from
static constexpr int kMaxPolicyLogs = 16;

static uint32_t gMask = kDefaultMask;

static const char *kHWLibsPaths[] {
	"/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/AMDRadeonX6000HWLibs.kext/Contents/MacOS/AMDRadeonX6000HWLibs"
};
static KernelPatcher::KextInfo kextHWLibs {
	"com.apple.kext.AMDRadeonX6000HWLibs",
	kHWLibsPaths, arrsize(kHWLibsPaths),
	{},
	{},
	KernelPatcher::KextInfo::Unloaded
};

// PECI_ReadRegistry(PECI *, const char *key, uint32_t *data, uint32_t defaultValue); 1 means success.
using t_readRegistry = int64_t (*)(void *peci, const char *key, uint32_t *data, uint32_t defaultValue);
static t_readRegistry orgReadRegistry {nullptr};

static int64_t wrapReadRegistry(void *peci, const char *key, uint32_t *data, uint32_t defaultValue) {
	int64_t result = orgReadRegistry(peci, key, data, defaultValue);
	if (key && data && strcmp(key, "PP_WorkLoadPolicyMask") == 0) {
		SYSLOG("vcnvp", "PP_WorkLoadPolicyMask read %u, answering %u (read result %lld)", *data, gMask, result);
		*data = gMask;
	}
	return result;
}

// SW_SMUM_Dpm_SetWorkloadPolicy(SMUM *, mask); 1 means the firmware accepted the message.
using t_setPolicy = int64_t (*)(void *smum, uint32_t mask);
static t_setPolicy orgSetPolicy {nullptr};

static int64_t wrapSetPolicy(void *smum, uint32_t mask) {
	static uint32_t lastMask = UINT32_MAX;
	static int64_t lastResult = INT64_MIN;
	static int logged = 0;
	int64_t result = orgSetPolicy(smum, mask);
	if ((mask != lastMask || result != lastResult) && logged < kMaxPolicyLogs) {
		SYSLOG("vcnvp", "firmware workload policy mask %u, result %lld", mask, result);
		logged++;
	}
	lastMask = mask;
	lastResult = result;
	return result;
}

static void onHWLibsLoad(void *, KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
	if (kextHWLibs.loadIndex != index)
		return;

	KernelPatcher::RouteRequest requests[] {
		{"_PECI_ReadRegistry", wrapReadRegistry, orgReadRegistry},
		{"_SW_SMUM_Dpm_SetWorkloadPolicy", wrapSetPolicy, orgSetPolicy},
	};
	if (patcher.routeMultiple(index, requests, address, size))
		SYSLOG("vcnvp", "routed, workload mask override %u", gMask);
	else {
		SYSLOG("vcnvp", "route failed (%d), driver left as it is", patcher.getError());
		patcher.clearError();
	}
}

static const char *bootargOff[]   { "-vcnvpoff" };
static const char *bootargDebug[] { "-vcnvpdbg" };
static const char *bootargBeta[]  { "-vcnvpbeta" };

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal,
	bootargOff,   arrsize(bootargOff),
	bootargDebug, arrsize(bootargDebug),
	bootargBeta,  arrsize(bootargBeta),
	KernelVersion::Tahoe,
	KernelVersion::Tahoe,
	[]() {
		if (getKernelMinorVersion() != kValidatedKernelMinor) {
			SYSLOG("vcnvp", "kernel minor %d is not validated, doing nothing", getKernelMinorVersion());
			return;
		}
		uint32_t requested = 0;
		if (PE_parse_boot_argn("vcnwlmask", &requested, sizeof(requested))) {
			if (requested >= 1 && requested <= kMaxMask)
				gMask = requested;
			else
				SYSLOG("vcnvp", "ignoring vcnwlmask=%u, using %u", requested, gMask);
		}
		lilu.onKextLoadForce(&kextHWLibs, 1, onHWLibsLoad, nullptr);
	}
};
