import sys, re, os

fp_ext = sys.argv[1]
fp_stubs = sys.argv[2]
fp_meson = sys.argv[3]

with open(fp_ext) as f: c = f.read()

NEVER_UNLOCK = {
    "VK_KHR_workgroup_memory_explicit_layout",
    "VK_KHR_portability_subset",
    "VK_EXT_validation_cache",
    "VK_EXT_validation_features",
    "VK_EXT_validation_flags",
    "VK_ANDROID_native_buffer",
    "VK_KHR_display",
    "VK_KHR_display_swapchain",
    "VK_EXT_direct_mode_display",
    "VK_EXT_acquire_drm_display",
    "VK_EXT_acquire_xlib_display",
}

all_exts = re.findall(r'Extension\s*\(\s*"(VK_[A-Z0-9_]+)"\s*,\s*(?:False|None)\s*,', c)
flipped = 0
for ext in all_exts:
    if ext in NEVER_UNLOCK:
        continue
    for pat in [
        rf'(Extension\s*\(\s*"{re.escape(ext)}"\s*,\s*)False(\s*,)',
        rf'(Extension\s*\(\s*"{re.escape(ext)}"\s*,\s*)None(\s*,)',
    ]:
        if re.search(pat, c):
            c = re.sub(pat, r'\1True\2', c)
            flipped += 1
            break

UPSCALER_EXTS = [
    "VK_AMD_anti_lag",
    "VK_KHR_shader_bfloat16",
    "VK_EXT_full_screen_exclusive",
]

added_exts = []
for ext in UPSCALER_EXTS:
    if ext in c:
        continue
    m = re.search(r'(device_extensions\s*=\s*\[)', c)
    if not m:
        m = re.search(r'(extensions\s*=\s*\[)', c)
    if m:
        ins = c.find('\n', m.end())
        entry = f'\n    Extension("{ext}", True, None),'
        c = c[:ins] + entry + c[ins:]
        added_exts.append(ext)

c += '\n# EXT_UNLOCK_APPLIED\n'
with open(fp_ext, 'w') as f: f.write(c)
print(f'[OK] Phase 1: flipped {flipped}, Phase 2: added {len(added_exts)} upscaler exts')

STUBS = """
#include "tu_device.h"
#include "tu_cmd_buffer.h"
#ifdef __cplusplus
extern "C" {
#endif

VKAPI_ATTR VkResult VKAPI_CALL
tu_GetPhysicalDeviceOpticalFlowImageFormatsNV(
   VkPhysicalDevice physicalDevice,
   const VkOpticalFlowImageFormatInfoNV *pInfo,
   uint32_t *pCount, VkOpticalFlowImageFormatPropertiesNV *pProps)
{ if (pCount) *pCount = 0; return VK_SUCCESS; }

VKAPI_ATTR VkResult VKAPI_CALL
tu_CreateOpticalFlowSessionNV(VkDevice d,
   const VkOpticalFlowSessionCreateInfoNV *pCI,
   const VkAllocationCallbacks *pA, VkOpticalFlowSessionNV *pS)
{ return VK_ERROR_FEATURE_NOT_PRESENT; }

VKAPI_ATTR void VKAPI_CALL
tu_DestroyOpticalFlowSessionNV(VkDevice d, VkOpticalFlowSessionNV s,
   const VkAllocationCallbacks *pA) {}

VKAPI_ATTR VkResult VKAPI_CALL
tu_BindOpticalFlowSessionImageNV(VkDevice d, VkOpticalFlowSessionNV s,
   VkOpticalFlowSessionBindingPointNV bp, VkImageView v, VkImageLayout l)
{ return VK_ERROR_FEATURE_NOT_PRESENT; }

VKAPI_ATTR void VKAPI_CALL
tu_CmdOpticalFlowExecuteNV(VkCommandBuffer cb,
   VkOpticalFlowSessionNV s, const VkOpticalFlowExecuteInfoNV *pEI) {}

VKAPI_ATTR VkResult VKAPI_CALL
tu_SetLatencySleepModeNV(VkDevice d, VkSwapchainKHR sc,
   const VkLatencySleepModeInfoNV *pSM)
{ return VK_SUCCESS; }

VKAPI_ATTR VkResult VKAPI_CALL
tu_LatencySleepNV(VkDevice d, VkSwapchainKHR sc,
   const VkLatencySleepInfoNV *pSI)
{ return VK_SUCCESS; }

VKAPI_ATTR void VKAPI_CALL
tu_SetLatencyMarkerNV(VkDevice d, VkSwapchainKHR sc,
   const VkSetLatencyMarkerInfoNV *pLMI) {}

VKAPI_ATTR void VKAPI_CALL
tu_GetLatencyTimingsNV(VkDevice d, VkSwapchainKHR sc,
   VkGetLatencyMarkerInfoNV *pLMI) {}

VKAPI_ATTR void VKAPI_CALL
tu_QueueNotifyOutOfBandNV(VkQueue q,
   const VkOutOfBandQueueTypeInfoNV *pQT) {}

VKAPI_ATTR void VKAPI_CALL
tu_AntiLagUpdateAMD(VkDevice d, const VkAntiLagDataAMD *pData) {}

VKAPI_ATTR VkResult VKAPI_CALL
tu_CreateCuModuleNVX(VkDevice d, const VkCuModuleCreateInfoNVX *pCI,
   const VkAllocationCallbacks *pA, VkCuModuleNVX *pM)
{ return VK_ERROR_FEATURE_NOT_PRESENT; }

VKAPI_ATTR VkResult VKAPI_CALL
tu_CreateCuFunctionNVX(VkDevice d, const VkCuFunctionCreateInfoNVX *pCI,
   const VkAllocationCallbacks *pA, VkCuFunctionNVX *pF)
{ return VK_ERROR_FEATURE_NOT_PRESENT; }

VKAPI_ATTR void VKAPI_CALL
tu_DestroyCuModuleNVX(VkDevice d, VkCuModuleNVX m,
   const VkAllocationCallbacks *pA) {}

VKAPI_ATTR void VKAPI_CALL
tu_DestroyCuFunctionNVX(VkDevice d, VkCuFunctionNVX f,
   const VkAllocationCallbacks *pA) {}

VKAPI_ATTR void VKAPI_CALL
tu_CmdCuLaunchKernelNVX(VkCommandBuffer cb,
   const VkCuLaunchInfoNVX *pLI) {}

VKAPI_ATTR VkResult VKAPI_CALL
tu_AcquireFullScreenExclusiveModeEXT(VkDevice d, VkSwapchainKHR sc)
{ return VK_SUCCESS; }

VKAPI_ATTR VkResult VKAPI_CALL
tu_ReleaseFullScreenExclusiveModeEXT(VkDevice d, VkSwapchainKHR sc)
{ return VK_SUCCESS; }

#ifdef __cplusplus
}
#endif
"""

with open(fp_stubs, 'w') as f: f.write(STUBS)
print(f'[OK] Phase 3: upscaler stubs written')

if os.path.exists(fp_meson):
    with open(fp_meson) as f: m = f.read()
    stub_entry = "'tu_upscaler_stubs.cc',"
    if stub_entry not in m:
        target = re.search(r'(freedreno_vulkan_files\s*=\s*files\s*\()', m)
        if target:
            ins = m.find('\n', target.end())
            m = m[:ins+1] + f'  {stub_entry}\n' + m[ins+1:]
            with open(fp_meson, 'w') as f: f.write(m)
            print('[OK] Phase 4: stubs added to meson.build')
        else:
            print('[WARN] Phase 4: freedreno_vulkan_files not found')
