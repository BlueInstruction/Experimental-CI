#include "include/wrapper.h"
#include <vulkan/vulkan.h>
#include <cstdint>
#include <cstring>
#include <vector>
#include <android/log.h>

#define LOG_TAG "DXWrapper/SPIRV"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

#define SPIRV_MAGIC              0x07230203u
#define SPIRV_OP_DECORATE        71u
#define SPIRV_OP_MEMBER_DECORATE 72u
#define SPIRV_DECORATION_CLIP_DISTANCE   3u
#define SPIRV_DECORATION_CULL_DISTANCE   4u
#define SPIRV_OP_CAPABILITY       17u
#define SPIRV_CAP_CLIP_DISTANCE   32u
#define SPIRV_CAP_CULL_DISTANCE   33u
#define SPIRV_OP_NOP               1u

static bool spirv_has_clip_cull(const uint32_t *words, size_t word_count) {
    if (word_count < 5 || words[0] != SPIRV_MAGIC) return false;
    size_t pos = 5;
    while (pos < word_count) {
        uint32_t word = words[pos];
        uint16_t op   = word & 0xFFFFu;
        uint16_t len  = word >> 16u;
        if (len == 0 || pos + len > word_count) break;
        if (op == SPIRV_OP_DECORATE && len >= 3) {
            uint32_t deco = words[pos + 2];
            if (deco == SPIRV_DECORATION_CLIP_DISTANCE ||
                deco == SPIRV_DECORATION_CULL_DISTANCE)
                return true;
        }
        if (op == SPIRV_OP_CAPABILITY && len >= 2) {
            uint32_t cap = words[pos + 1];
            if (cap == SPIRV_CAP_CLIP_DISTANCE || cap == SPIRV_CAP_CULL_DISTANCE)
                return true;
        }
        pos += len;
    }
    return false;
}

static void spirv_strip_clip_cull_decorations(uint32_t *words, size_t word_count) {
    if (word_count < 5) return;
    size_t pos = 5;
    while (pos < word_count) {
        uint32_t word = words[pos];
        uint16_t op   = word & 0xFFFFu;
        uint16_t len  = word >> 16u;
        if (len == 0 || pos + len > word_count) break;
        if (op == SPIRV_OP_DECORATE && len >= 3) {
            uint32_t deco = words[pos + 2];
            if (deco == SPIRV_DECORATION_CLIP_DISTANCE ||
                deco == SPIRV_DECORATION_CULL_DISTANCE) {
                LOGD("NOP-ing OpDecorate clip/cull at word %zu", pos);
                for (uint16_t i = 0; i < len; i++)
                    words[pos + i] = (i == 0) ? ((uint32_t)len << 16) | SPIRV_OP_NOP : 0;
            }
        }
        if (op == SPIRV_OP_CAPABILITY && len >= 2) {
            uint32_t cap = words[pos + 1];
            if (cap == SPIRV_CAP_CLIP_DISTANCE || cap == SPIRV_CAP_CULL_DISTANCE) {
                LOGD("NOP-ing OpCapability clip/cull at word %zu", pos);
                for (uint16_t i = 0; i < len; i++)
                    words[pos + i] = (i == 0) ? ((uint32_t)len << 16) | SPIRV_OP_NOP : 0;
            }
        }
        if (op == SPIRV_OP_MEMBER_DECORATE && len >= 4) {
            uint32_t deco = words[pos + 3];
            if (deco == SPIRV_DECORATION_CLIP_DISTANCE ||
                deco == SPIRV_DECORATION_CULL_DISTANCE) {
                LOGD("NOP-ing OpMemberDecorate clip/cull at word %zu", pos);
                for (uint16_t i = 0; i < len; i++)
                    words[pos + i] = (i == 0) ? ((uint32_t)len << 16) | SPIRV_OP_NOP : 0;
            }
        }
        pos += len;
    }
}

bool wrapper_patch_shader(
    const WrapperDeviceInfo *info,
    const WrapperEnvConfig *cfg,
    const uint32_t *spirv_in,
    size_t spirv_size_bytes,
    std::vector<uint32_t> &spirv_out)
{
    size_t word_count = spirv_size_bytes / sizeof(uint32_t);
    spirv_out.assign(spirv_in, spirv_in + word_count);

    bool patched = false;

    bool do_strip_clip = false;
    if (cfg->disable_clip_distance) {
        do_strip_clip = true;
    } else if (info->vendor == GPU_VENDOR_MALI && !info->supports_clip_distance) {
        do_strip_clip = !cfg->force_clip_distance;
    }

    if (do_strip_clip && spirv_has_clip_cull(spirv_out.data(), word_count)) {
        LOGI("Stripping ClipDistance/CullDistance from shader (Mali HW lacks support)");
        spirv_strip_clip_cull_decorations(spirv_out.data(), word_count);
        patched = true;
    }

    return patched;
}

VkResult wrapper_create_shader_module(
    VkDevice device,
    const VkShaderModuleCreateInfo *ci,
    const VkAllocationCallbacks *alloc,
    VkShaderModule *pShaderModule,
    const WrapperDeviceInfo *info,
    const WrapperEnvConfig *cfg,
    PFN_vkCreateShaderModule next_fn)
{
    if (!ci || !ci->pCode || ci->codeSize < 20)
        return next_fn(device, ci, alloc, pShaderModule);

    const uint32_t *words = ci->pCode;
    if (words[0] != SPIRV_MAGIC)
        return next_fn(device, ci, alloc, pShaderModule);

    std::vector<uint32_t> patched_spirv;
    bool did_patch = wrapper_patch_shader(info, cfg, words, ci->codeSize, patched_spirv);

    if (did_patch) {
        VkShaderModuleCreateInfo patched_ci = *ci;
        patched_ci.pCode    = patched_spirv.data();
        patched_ci.codeSize = patched_spirv.size() * sizeof(uint32_t);
        return next_fn(device, &patched_ci, alloc, pShaderModule);
    }

    return next_fn(device, ci, alloc, pShaderModule);
}
