#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

WORKDIR="${GITHUB_WORKSPACE:-$(pwd)}/build"
MESA_DIR="${WORKDIR}/mesa"
PATCHES_DIR="$(pwd)/patches"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_MIRROR="https://github.com/mesa3d/mesa.git"

MESA_SOURCE="${MESA_SOURCE:-main_branch}"
STAGING_BRANCH="${STAGING_BRANCH:-staging/26.0}"
CUSTOM_TAG="${CUSTOM_TAG:-}"
BUILD_TYPE="${BUILD_TYPE:-release}"
BUILD_VARIANT="${BUILD_VARIANT:-optimized}"
NDK_PATH="${NDK_PATH:-/opt/android-ndk}"
API_LEVEL="${API_LEVEL:-35}"
TARGET_GPU="${TARGET_GPU:-a7xx}"

ENABLE_EXT_SPOOF="${ENABLE_EXT_SPOOF:-true}"
ENABLE_DECK_EMU="${ENABLE_DECK_EMU:-true}"
DECK_EMU_TARGET="${DECK_EMU_TARGET:-nvidia}"
ENABLE_TIMELINE_HACK="${ENABLE_TIMELINE_HACK:-true}"
ENABLE_CUSTOM_FLAGS="${ENABLE_CUSTOM_FLAGS:-true}"
APPLY_GRAPHICS_PATCHES="${APPLY_GRAPHICS_PATCHES:-true}"

CUSTOM_TU_DEBUG="${CUSTOM_TU_DEBUG:-push_regs,ubwc_all,defrag,unroll,turbo}"

CFLAGS_EXTRA="${CFLAGS_EXTRA:--O3 -march=armv8.2-a+fp16+rcpc+dotprod -ffast-math -fno-finite-math-only}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:--O3 -march=armv8.2-a+fp16+rcpc+dotprod -ffast-math -fno-finite-math-only -fno-exceptions}"
LDFLAGS_EXTRA="${LDFLAGS_EXTRA:--Wl,--gc-sections -Wl,--icf=safe}"

check_struct_member() {
    local file="$1"
    local struct="$2"
    local member="$3"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi    
    python3 - "$file" "$struct" "$member" << 'PYEOF'
import sys, re
fp, struct_name, member = sys.argv[1], sys.argv[2], sys.argv[3]
with open(fp) as f: content = f.read()
pattern = rf'struct\s+{re.escape(struct_name)}\s*\{{([^}}]+)\}}'
match = re.search(pattern, content, re.DOTALL)
if match:
    struct_body = match.group(1)
    if '.' in member:
        parts = member.split('.')
        current = struct_body
        for part in parts:
            if re.search(rf'\b{re.escape(part)}\b', current):
                current = ""
            else:
                print("NOT_FOUND")
                sys.exit(0)
        print("FOUND")
    else:
        if re.search(rf'\b{re.escape(member)}\b', struct_body):
            print("FOUND")
        else:
            print("NOT_FOUND")
else:
    print("STRUCT_NOT_FOUND")
PYEOF
}

verify_injection_safety() {
    log_info "Verifying injection safety"
    
    local tu_util_h="${MESA_DIR}/src/freedreno/vulkan/tu_util.h"
    local tu_device_cc="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"
    local tu_image_cc="${MESA_DIR}/src/freedreno/vulkan/tu_image.cc"
    
    for flag in push_regs ubwc_all defrag unroll turbo deck_emu; do
        if ! grep -q "TU_DEBUG_${flag^^}" "$tu_util_h" 2>/dev/null; then
            log_warn "TU_DEBUG_${flag^^} not defined - will be added"
        fi
    done
    
    if grep -q "ext->KHR_mir_surface" "$tu_device_cc" 2>/dev/null; then
        log_error "Unsafe extension injection detected in tu_device.cc"
        return 1
    fi
    
    if grep -q "image->plane_count" "$tu_image_cc" 2>/dev/null; then
        if ! check_struct_member "$tu_image_cc" "tu_image" "plane_count" | grep -q "FOUND"; then
            log_error "Unsafe plane_count usage in tu_image.cc"            return 1
        fi
    fi
    
    log_success "Injection safety verified"
    return 0
}

check_deps() {
    local deps="git meson ninja patchelf zip ccache curl python3"
    for dep in $deps; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Missing dependency: $dep"
            exit 1
        fi
    done
    log_success "Dependencies check passed"
}

fetch_latest_release() {
    local tags=""
    tags=$(git ls-remote --tags --refs "$MESA_REPO" 2>/dev/null | \
        grep -oE 'mesa-[0-9]+\.[0-9]+\.[0-9]+$' | \
        sort -V | tail -1) || true
    if [[ -z "$tags" ]]; then
        tags=$(git ls-remote --tags --refs "$MESA_MIRROR" 2>/dev/null | \
            grep -oE 'mesa-[0-9]+\.[0-9]+\.[0-9]+$' | \
            sort -V | tail -1) || true
    fi
    [[ -z "$tags" ]] && { log_error "Could not determine latest release"; exit 1; }
    echo "$tags"
}

get_mesa_version() {
    [[ -f "${MESA_DIR}/VERSION" ]] && cat "${MESA_DIR}/VERSION" || echo "unknown"
}

get_vulkan_version() {
    local vk_header="${MESA_DIR}/include/vulkan/vulkan_core.h"
    if [[ -f "$vk_header" ]]; then
        local major minor patch
        major=$(grep -m1 "#define VK_HEADER_VERSION_COMPLETE" "$vk_header" | grep -oP 'VK_MAKE_API_VERSION\(\d+,\s*\K\d+' || echo "1")
        minor=$(grep -m1 "#define VK_HEADER_VERSION_COMPLETE" "$vk_header" | grep -oP 'VK_MAKE_API_VERSION\(\d+,\s*\d+,\s*\K\d+' || echo "4")
        patch=$(grep -m1 "#define VK_HEADER_VERSION" "$vk_header" | awk '{print $3}' || echo "0")
        echo "${major}.${minor}.${patch}"
    else
        echo "1.4.0"
    fi
}
prepare_workdir() {
    log_info "Preparing build directory"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    log_success "Build directory ready"
}

clone_mesa() {
    log_info "Cloning Mesa source"
    local clone_args=()
    local target_ref=""
    local repo_url="$MESA_REPO"

    if [[ "$BUILD_VARIANT" == "autotuner" ]]; then
        repo_url="https://gitlab.freedesktop.org/PixelyIon/mesa.git"
        target_ref="tu-newat"
        clone_args=("--depth" "1" "--branch" "$target_ref")
    else
        case "$MESA_SOURCE" in
            latest_release)
                target_ref=$(fetch_latest_release)
                clone_args=("--depth" "1" "--branch" "$target_ref")
                ;;
            staging_branch)
                target_ref="$STAGING_BRANCH"
                clone_args=("--depth" "1" "--branch" "$target_ref")
                ;;
            main_branch|latest_main)
                target_ref="main"
                clone_args=("--depth" "1" "--branch" "main")
                ;;
            custom_tag)
                [[ -z "$CUSTOM_TAG" ]] && { log_error "Custom tag not specified"; exit 1; }
                target_ref="$CUSTOM_TAG"
                clone_args=("--depth" "1" "--branch" "$target_ref")
                ;;
        esac
    fi

    log_info "Target: $target_ref"
    if ! git clone "${clone_args[@]}" "$repo_url" "$MESA_DIR" 2>/dev/null; then
        log_warn "Primary source failed, trying mirror"
        if ! git clone "${clone_args[@]}" "$MESA_MIRROR" "$MESA_DIR" 2>/dev/null; then
            log_error "Failed to clone Mesa"
            exit 1
        fi
    fi

    cd "$MESA_DIR"
    git config user.email "ci@turnip.builder"    git config user.name "Turnip CI Builder"
    
    local version=$(get_mesa_version)
    local commit=$(git rev-parse --short=8 HEAD)
    echo "$version" > "${WORKDIR}/version.txt"
    echo "$commit"  > "${WORKDIR}/commit.txt"
    log_success "Mesa $version ($commit) ready"
}

apply_conditional_flush_patch() {
    log_info "Applying: Conditional Cache Flush Patch"
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_cmd_buffer.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

new_func = '''
static void
tu_emit_conditional_cache_flush(struct tu_cmd_buffer *cmd,
                                VkPipelineStageFlags2 src_stage,
                                VkPipelineStageFlags2 dst_stage)
{
    if (src_stage == dst_stage)
        return;
    
    if ((src_stage & VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT) &&
        (dst_stage & VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT)) {
        if (!(cmd->state.pending_memory_ops & TU_PENDING_MEMORY_WRITE))
            return;
    }
    
    tu_emit_cache_flush(cmd, src_stage, dst_stage);
}
'''

includes = list(re.finditer(r'^#include\b.*', content, re.MULTILINE))
if includes:
    eol = content.find('\n', includes[-1].start())
    content = content[:eol+1] + new_func + '\n' + content[eol+1:]

with open(fp, 'w') as f: f.write(content)
print("[OK] Conditional flush patch applied")
PYEOF
}

apply_bindless_pool_patch() {
    log_info "Applying: Bindless Descriptor Pool Expansion"    local file="${MESA_DIR}/src/freedreno/vulkan/tu_descriptor_set.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

match = re.search(r'(VkResult\s+tu_descriptor_set_layout_create\s*\([^)]*\)\s*\{)', content)
if not match:
    print("[WARN] Could not find tu_descriptor_set_layout_create")
    sys.exit(0)

pool_code = '''
    uint32_t bindless_count = 0;
    for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
        if (pCreateInfo->pBindings[i].descriptorCount > 1024 &&
            (pCreateInfo->pBindings[i].stageFlags & VK_SHADER_STAGE_FRAGMENT_BIT)) {
            bindless_count += pCreateInfo->pBindings[i].descriptorCount;
        }
    }
    if (bindless_count > 4096) {
        *pSetLayout = (*pSetLayout) ? (*pSetLayout) * 2 : 2;
    }
'''

inject_pos = match.end()
content = content[:inject_pos] + '\n' + pool_code + content[inject_pos:]

with open(fp, 'w') as f: f.write(content)
print("[OK] Bindless pool expansion applied")
PYEOF
}

apply_ubwc_format_patch() {
    log_info "Applying: UBWC Fix for ASTC/BC Formats"
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_image.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

ubwc_match = re.search(r'(bool\s+tu_format_supports_ubwc\s*\([^)]*\)[^{]*\{)', content)
if ubwc_match:
    func_start = ubwc_match.end()
    brace_count = 1
    pos = func_start
    while pos < len(content) and brace_count > 0:        if content[pos] == '{': brace_count += 1
        elif content[pos] == '}': brace_count -= 1
        pos += 1
    
    func_body = content[func_start:pos-1]
    if 'return false' in func_body or 'return true' in func_body:
        new_code = '''
    switch (format) {
        case VK_FORMAT_ASTC_4x4_SRGB_BLOCK:
        case VK_FORMAT_ASTC_4x4_UNORM_BLOCK:
        case VK_FORMAT_ASTC_8x8_SRGB_BLOCK:
        case VK_FORMAT_BC7_SRGB_BLOCK:
        case VK_FORMAT_BC7_UNORM_BLOCK:
            return true;
        default:
            break;
    }
'''
        returns = list(re.finditer(r'\breturn\s+(true|false)\s*;', func_body))
        if returns:
            last_ret = returns[-1]
            insert_pos = func_start + last_ret.start()
            content = content[:insert_pos] + new_code + '\n    ' + content[insert_pos:]

with open(fp, 'w') as f: f.write(content)
print("[OK] UBWC format fix applied")
PYEOF
}

apply_depth_mode_patch() {
    log_info "Applying: Depth Mode Override for AC Games"
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_pipeline.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

match = re.search(r'(static\s+void\s+tu_pipeline_graphics_init_depth\s*\([^)]*\))', content)
if not match:
    match = re.search(r'(pipeline->depth_mode\s*=)', content)

if match:
    depth_code = '''
    if (pipeline->device->app_key && 
        (strstr(pipeline->device->app_key, "AC_Mirage") ||
         strstr(pipeline->device->app_key, "AC_Valhalla") ||
         strstr(pipeline->device->app_key, "Horizon"))) {
        pipeline->depth_mode = VK_DEPTH_MODE_REVERSED;        pipeline->depth_compare_op = VK_COMPARE_OP_GREATER;
    }
'''
    inject_pos = match.end()
    content = content[:inject_pos] + '\n' + depth_code + content[inject_pos:]

with open(fp, 'w') as f: f.write(content)
print("[OK] Depth mode patch applied")
PYEOF
}

apply_gmem_resolve_patch() {
    log_info "Applying: GMEM Resolve Safety Patch"
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_pass.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

match = re.search(r'(static\s+bool\s+tu_attachment_needs_resolve\s*\([^)]*\))', content)
if match:
    resolve_code = '''
    if (final_layout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL ||
        final_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
        return true;
    }
    if (attachment->store_op == VK_ATTACHMENT_STORE_OP_DONT_CARE) {
        if (!(attachment->usage & VK_IMAGE_USAGE_SAMPLED_BIT)) {
            return false;
        }
    }
'''
    brace_match = re.search(r'\{', content[match.end():])
    if brace_match:
        inject_pos = match.end() + brace_match.end()
        content = content[:inject_pos] + '\n' + resolve_code + content[inject_pos:]

with open(fp, 'w') as f: f.write(content)
print("[OK] GMEM resolve patch applied")
PYEOF
}

apply_pipeline_cache_patch() {
    log_info "Applying: Pipeline Cache Improvement"
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_pipeline_cache.c"
    [[ ! -f "$file" ]] && return 0
    
    python3 - "$file" << 'PYEOF'import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

if 'tu_pipeline_cache_hash' in content:
    content = re.sub(
        r'(_mesa_hash_data\([^)]+\))',
        r'_mesa_hash_murmur(\1, 0xDEADBEEF)',
        content
    )
    print("[OK] Pipeline cache hashing improved")

content = re.sub(
    r'#define\s+TU_PIPELINE_CACHE_MAX_SIZE\s+\S+',
    '#define TU_PIPELINE_CACHE_MAX_SIZE (512 * 1024 * 1024)',
    content
)

with open(fp, 'w') as f: f.write(content)
print("[OK] Pipeline cache patch applied")
PYEOF
}

apply_graphics_patches() {
    log_info "Applying graphics fix patches for AAA games"
    
    apply_conditional_flush_patch
    apply_bindless_pool_patch
    apply_ubwc_format_patch
    apply_depth_mode_patch
    apply_gmem_resolve_patch
    apply_pipeline_cache_patch
    
    log_success "All graphics patches applied"
}

apply_turbo_mode() {
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

turbo_func = '''
static void
tu_try_activate_turbo(void)
{
    static const char * const paths[] = {
        "/sys/class/kgsl/kgsl-3d0/min_pwrlevel",
        "/sys/class/devfreq/kgsl-3d0/min_freq",        NULL,
    };
    for (int i = 0; paths[i]; i++) {
        int fd = open(paths[i], O_WRONLY | O_CLOEXEC);
        if (fd >= 0) {
            (void)write(fd, "0", 1);
            close(fd);
            break;
        }
    }
}
'''

includes = list(re.finditer(r'^#include\b.*', content, re.MULTILINE))
if includes and 'tu_try_activate_turbo' not in content:
    eol = content.find('\n', includes[-1].start())
    content = content[:eol+1] + turbo_func + '\n' + content[eol+1:]

call_match = re.search(r'(tu_physical_device_init\s*\([^)]*\)[^{]*\{)', content)
if call_match and 'tu_try_activate_turbo' not in content:
    inject_pos = call_match.end()
    call_code = '''
    if (TU_DEBUG(TURBO))
        tu_try_activate_turbo();
'''
    content = content[:inject_pos] + '\n' + call_code + content[inject_pos:]

with open(fp, 'w') as f: f.write(content)
print('[OK] TU_DEBUG_TURBO applied')
PYEOF
}

apply_ubwc_all_fixed() {
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_image.cc"
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

ubwc_code = '''
   if (TU_DEBUG(UBWC_ALL) && image->vk.format != VK_FORMAT_UNDEFINED) {
      if (!vk_format_is_depth_or_stencil(image->vk.format) &&
          !vk_format_is_compressed(image->vk.format)) {
         image->layout.ubwc = true;
         if (!image->layout.ubwc_compatible)
            image->layout.ubwc_compatible = true;
      }
   }
'''
match = re.search(r'(image->layout\.[a-zA-Z_]+\s*=\s*[^;]+;)', content)
if match:
    inject_pos = match.end()
    content = content[:inject_pos] + '\n' + ubwc_code + content[inject_pos:]
    with open(fp, 'w') as f: f.write(content)
    print('[OK] TU_DEBUG_UBWC_ALL applied with correct Mesa 26.x API')
else:
    print('[WARN] Could not find safe injection point for ubwc_all')
PYEOF
}

apply_defrag_fixed() {
    local file="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

defrag_code = '''
   if (TU_DEBUG(DEFRAG) && size > (1u << 20)) {
      size = ALIGN_POT(size, 64 * 1024);
   }
'''

match = re.search(r'(return\s+tu_bo_alloc\([^)]+\);)', content)
if match:
    inject_pos = match.start()
    content = content[:inject_pos] + defrag_code + '\n   ' + content[inject_pos:]
    with open(fp, 'w') as f: f.write(content)
    print('[OK] TU_DEBUG_DEFRAG applied')
else:
    print('[WARN] Could not find safe injection point for defrag')
PYEOF
}

apply_unroll_fixed() {
    local file="${MESA_DIR}/src/freedreno/ir3/ir3_compiler_nir.c"
    python3 - "$file" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

unroll_code = '''
   if (TU_DEBUG(UNROLL)) {
      NIR_PASS(progress, nir, nir_opt_loop_unroll, nir_var_shader_temp);
   }
'''

match = re.search(r'(return\s+progress;|return\s+shader;)', content)
if match:    inject_pos = match.start()
    if re.search(r'nir_shader\s*\*\s*ir3_compile_shader', content[:inject_pos]):
        content = content[:inject_pos] + unroll_code + '\n   ' + content[inject_pos:]
        with open(fp, 'w') as f: f.write(content)
        print('[OK] TU_DEBUG_UNROLL applied')
    else:
        print('[WARN] Not in correct function for unroll')
else:
    print('[WARN] Could not find safe injection point for unroll')
PYEOF
}

apply_custom_debug_flags() {
    log_info "Adding custom TU_DEBUG flags with Mesa 26.x compatibility"
    
    local tu_util_h="${MESA_DIR}/src/freedreno/vulkan/tu_util.h"
    local tu_util_cc="${MESA_DIR}/src/freedreno/vulkan/tu_util.cc"
    
    [[ ! -f "$tu_util_h" ]] && { log_warn "tu_util.h not found"; return 0; }
    
    python3 - "$tu_util_h" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

flags_to_add = [
    'TU_DEBUG_FORCE_VRS', 'TU_DEBUG_PUSH_REGS', 'TU_DEBUG_UBWC_ALL',
    'TU_DEBUG_SLC_PIN', 'TU_DEBUG_TURBO', 'TU_DEBUG_DEFRAG',
    'TU_DEBUG_CP_PREFETCH', 'TU_DEBUG_SHFL', 'TU_DEBUG_VGT_PREF',
    'TU_DEBUG_UNROLL', 'TU_DEBUG_DECK_EMU',
]

existing = re.findall(r'TU_DEBUG_(\w+)\s*=\s*BITFIELD64_BIT', content)
to_add = [f for f in flags_to_add if f not in existing]

if not to_add:
    print('[OK] All custom flags already defined')
    sys.exit(0)

bits = list(map(int, re.findall(r'BITFIELD64_BIT\((\d+)\)', content)))
next_bit = max(bits) + 1 if bits else 37

new_lines = '\n'.join(f'   {flag:<32} = BITFIELD64_BIT({next_bit + i}),' 
                      for i, flag in enumerate(to_add))

all_defs = list(re.finditer(r'   TU_DEBUG_\w+\s*=\s*BITFIELD64_BIT\(\d+\),?', content))
if all_defs:
    last = all_defs[-1]
    eol = content.find('\n', last.end())
    content = content[:eol+1] + new_lines + '\n' + content[eol+1:]    with open(fp, 'w') as f: f.write(content)
    print(f'[OK] Added {len(to_add)} custom TU_DEBUG flags starting at bit {next_bit}')
else:
    print('[WARN] Could not find enum insertion point')
PYEOF

    python3 - "$tu_util_cc" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: content = f.read()

new_entries = '\n'.join([
    '   { "force_vrs",   TU_DEBUG_FORCE_VRS   },',
    '   { "push_regs",   TU_DEBUG_PUSH_REGS   },',
    '   { "ubwc_all",    TU_DEBUG_UBWC_ALL    },',
    '   { "slc_pin",     TU_DEBUG_SLC_PIN     },',
    '   { "turbo",       TU_DEBUG_TURBO       },',
    '   { "defrag",      TU_DEBUG_DEFRAG      },',
    '   { "cp_prefetch", TU_DEBUG_CP_PREFETCH },',
    '   { "shfl",        TU_DEBUG_SHFL        },',
    '   { "vgt_pref",    TU_DEBUG_VGT_PREF    },',
    '   { "unroll",      TU_DEBUG_UNROLL      },',
    '   { "deck_emu",    TU_DEBUG_DECK_EMU    },',
])

entries = list(re.finditer(r'\{\s*"[a-z_]+"\s*,\s*TU_DEBUG_\w+\s*\}', content))
if entries:
    last = entries[-1]
    eol = content.find('\n', last.end())
    content = content[:eol+1] + new_entries + '\n' + content[eol+1:]
    with open(fp, 'w') as f: f.write(content)
    print('[OK] Added custom entries to debug table')
else:
    print('[WARN] Debug table not found')
PYEOF

    if [[ -f "${MESA_DIR}/src/freedreno/vulkan/tu_device.cc" ]]; then
        apply_turbo_mode
    fi
    
    if [[ -f "${MESA_DIR}/src/freedreno/vulkan/tu_image.cc" ]]; then
        apply_ubwc_all_fixed
    fi
    
    if [[ -f "${MESA_DIR}/src/freedreno/vulkan/tu_device.cc" ]]; then
        apply_defrag_fixed
    fi
    
    if [[ -f "${MESA_DIR}/src/freedreno/ir3/ir3_compiler_nir.c" ]]; then
        apply_unroll_fixed    fi
    
    log_success "All custom TU_DEBUG flags applied with Mesa 26.x compatibility"
}

apply_timeline_semaphore_fix() {
    log_info "Applying timeline semaphore optimization"
    local target_file="${MESA_DIR}/src/vulkan/runtime/vk_sync_timeline.c"
    [[ ! -f "$target_file" ]] && return 0
    
    if git apply --check "${WORKDIR}/timeline.patch" 2>/dev/null; then
        git apply "${WORKDIR}/timeline.patch"
        log_success "Timeline semaphore fix applied"
    else
        log_warn "Timeline patch may have partially applied"
    fi
}

apply_gralloc_ubwc_fix() {
    log_info "Applying gralloc UBWC detection fix"
    local gralloc_file="${MESA_DIR}/src/util/u_gralloc/u_gralloc_fallback.c"
    [[ ! -f "$gralloc_file" ]] && return 0
    
    if git apply --check "${WORKDIR}/gralloc.patch" 2>/dev/null; then
        git apply "${WORKDIR}/gralloc.patch"
        log_success "Gralloc UBWC fix applied"
    else
        log_warn "Gralloc patch may have partially applied"
    fi
}

apply_deck_emu_support() {
    log_info "Applying deck_emu debug option (target: ${DECK_EMU_TARGET})"
    local tu_util_h="${MESA_DIR}/src/freedreno/vulkan/tu_util.h"
    local tu_util_cc="${MESA_DIR}/src/freedreno/vulkan/tu_util.cc"
    local tu_device_cc="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"

    if [[ -f "$tu_util_h" ]] && ! grep -q "TU_DEBUG_DECK_EMU" "$tu_util_h"; then
        local last_bit=$(grep -oP 'BITFIELD64_BIT\(\K[0-9]+' "$tu_util_h" | sort -n | tail -1)
        local new_bit=$((last_bit + 1))
        sed -i "/TU_DEBUG_FORCE_CONCURRENT_BINNING/a\\   TU_DEBUG_DECK_EMU = BITFIELD64_BIT(${new_bit})," "$tu_util_h" 2>/dev/null || true
    fi

    if [[ -f "$tu_util_cc" ]] && ! grep -q "deck_emu" "$tu_util_cc"; then
        sed -i '/{ "forcecb"/a\   { "deck_emu", TU_DEBUG_DECK_EMU },' "$tu_util_cc" 2>/dev/null || true
    fi

    if [[ -f "$tu_device_cc" ]] && ! grep -q "DECK_EMU" "$tu_device_cc"; then
        local driver_id driver_name device_name vendor_id device_id
        case "${DECK_EMU_TARGET}" in            nvidia)
                driver_id="VK_DRIVER_ID_NVIDIA_PROPRIETARY"; driver_name="NVIDIA"; device_name="NVIDIA GeForce RTX 4090"; vendor_id="0x10de"; device_id="0x2684"
                ;;
            amd|*)
                driver_id="VK_DRIVER_ID_MESA_RADV"; driver_name="radv"; device_name="AMD RADV VANGOGH"; vendor_id="0x1002"; device_id="0x163f"
                ;;
        esac
        python3 - "$tu_device_cc" "$driver_id" "$driver_name" "$device_name" "$vendor_id" "$device_id" << 'PYEOF'
import sys, re
fp  = sys.argv[1]
did = sys.argv[2]
dn  = sys.argv[3]
dv  = sys.argv[4]
vid = int(sys.argv[5], 16)
devid = int(sys.argv[6], 16)
with open(fp) as f: c = f.read()
inj = (
    '\nif (TU_DEBUG(DECK_EMU)) {\n'
    '   p->driverID = ' + did + ';\n'
    '   memset(p->driverName, 0, sizeof(p->driverName));\n'
    '   snprintf(p->driverName, VK_MAX_DRIVER_NAME_SIZE, "' + dn + '");\n'
    '   memset(p->driverInfo, 0, sizeof(p->driverInfo));\n'
    '   snprintf(p->driverInfo, VK_MAX_DRIVER_INFO_SIZE, "Mesa (spoofed)");\n'
    '}\n'
)
m = re.search(r'(\n[ \t]*p->denormBehaviorIndependence\s*=)', c)
if m:
    c = c[:m.start()] + '\n' + inj + c[m.start():]
    done = True
if not done:
    fm = re.search(r'tu_get_physical_device_properties_1_2\s*\([^)]*\)\s*\{', c)
    if fm:
        d = 1; p = fm.end()
        while p < len(c) and d > 0:
            if c[p] == '{': d += 1
            elif c[p] == '}': d -= 1
            p += 1
        c = c[:p-1] + '\n' + inj + c[p-1:]
        done = True
if done:
    with open(fp, 'w') as f: f.write(c)
    print('[OK] deck_emu applied: ' + did)
else:
    print('[WARN] deck_emu: no injection point found, skipping')
PYEOF
        log_success "deck_emu spoofing applied"
    fi
}

apply_vulkan_extensions_support() {    log_info "Enabling Vulkan extensions and D3D features"
    local tu_device="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"
    local vk_exts_py="${MESA_DIR}/src/vulkan/util/vk_extensions.py"
    [[ ! -f "$tu_device" ]] && return 0

    if [[ -f "$vk_exts_py" ]]; then
        python3 - "$vk_exts_py" "$tu_device" << 'PYEOF'
import sys, re
vk_path, tu_path = sys.argv[1], sys.argv[2]

with open(vk_path) as f: vk_content = f.read()
with open(tu_path) as f: tu_content = f.read()

device_ext_fields = set()
struct_match = re.search(r'struct\s+vk_device_extension_table\s*\{([^}]+)\}', vk_content, re.DOTALL)
if struct_match:
    struct_body = struct_match.group(1)
    for line in struct_body.split('\n'):
        m = re.match(r'\s*bool\s+([a-zA-Z0-9_]+)\s*;', line)
        if m:
            device_ext_fields.add(m.group(1))

print(f"[INFO] Found {len(device_ext_fields)} valid device extension fields")

SAFE_EXTENSIONS = {
    "VK_KHR_maintenance4", "VK_KHR_maintenance5", "VK_KHR_maintenance6",
    "VK_KHR_dynamic_rendering", "VK_KHR_dynamic_rendering_local_read",
    "VK_EXT_descriptor_indexing", "VK_EXT_descriptor_buffer",
    "VK_EXT_robustness2", "VK_KHR_robustness2",
    "VK_EXT_format_feature_flags2", "VK_KHR_format_feature_flags2",
    "VK_KHR_synchronization2",
    "VK_ANDROID_external_memory_android_hardware_buffer",
    "VK_QCOM_render_pass_shader_resolve",
}

injection_lines = []
for ext_name in SAFE_EXTENSIONS:
    field_name = ext_name.replace("VK_", "")
    field_name = re.sub(r'_(KHR|EXT|AMD|VALVE|QCOM|MESA)_', '_', field_name)
    field_name = field_name.lower()
    
    if field_name in device_ext_fields:
        injection_lines.append(f"    ext->{field_name} = true;")

if injection_lines:
    inject_pattern = r'(ext->[a-zA-Z_]+\s*=\s*(true|false);)'
    match = re.search(inject_pattern, tu_content)
    
    if match:
        inject_pos = match.start()        new_code = '\n'.join(injection_lines) + '\n'
        tu_content = tu_content[:inject_pos] + new_code + tu_content[inject_pos:]
        
        with open(tu_path, 'w') as f:
            f.write(tu_content)
        print(f"[OK] Injected {len(injection_lines)} safe extensions into tu_device.cc")
    else:
        print("[WARN] Could not find injection point in tu_device.cc")
else:
    print("[INFO] No safe extensions to inject")
PYEOF
        log_success "vk_extensions.py patched"
    fi
}

apply_a8xx_device_support() {
    log_info "Applying A8xx device support patches"
    local knl_kgsl="${MESA_DIR}/src/freedreno/vulkan/tu_knl_kgsl.cc"

    if [[ -f "$knl_kgsl" ]] && ! grep -q "case 5:" "$knl_kgsl"; then
        python3 - "$knl_kgsl" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f:
    c = f.read()
inject = (
    '   case 5:\n'
    '   case 6:\n'
    '      device->ubwc_config.bank_swizzle_levels = 0x6;\n'
    '      device->ubwc_config.macrotile_mode = 1;\n'
    '      break;\n'
)
pat = r'(case.*?UBWC_4_0:.*?break;\n)([ \t]*default:)'
m = re.search(pat, c, re.DOTALL)
if m:
    c = c[:m.start(2)] + inject + c[m.start(2):]
    with open(fp, 'w') as f:
        f.write(c)
    print('[OK] UBWC 5/6 cases inserted')
else:
    print('[WARN] UBWC switch pattern not found')
PYEOF
        log_success "UBWC 5/6 support applied"
    else
        log_info "UBWC 5/6: already patched or file not found"
    fi

    log_success "A8xx support applied"
}
apply_patches() {
    log_info "Applying patches for $TARGET_GPU"
    cd "$MESA_DIR"
    
    if [[ "$BUILD_VARIANT" == "vanilla" ]]; then
        log_info "Vanilla build - skipping all patches"
        return 0
    fi
    
    if [[ "$ENABLE_TIMELINE_HACK" == "true" ]]; then
        apply_timeline_semaphore_fix
    fi
    
    if [[ "$ENABLE_CUSTOM_FLAGS" == "true" ]]; then
        apply_custom_debug_flags
    fi
    
    if [[ "$ENABLE_DECK_EMU" == "true" ]]; then
        apply_deck_emu_support
    fi
    
    if [[ "$ENABLE_EXT_SPOOF" == "true" ]]; then
        apply_vulkan_extensions_support
    fi
    
    if [[ "$TARGET_GPU" == "a8xx" ]]; then
        apply_a8xx_device_support
    fi
    
    if [[ "$APPLY_GRAPHICS_PATCHES" == "true" ]]; then
        apply_graphics_patches
    fi
    
    if [[ -d "$PATCHES_DIR" ]]; then
        for patch in "$PATCHES_DIR"/*.patch; do
            [[ ! -f "$patch" ]] && continue
            local patch_name=$(basename "$patch")
            if [[ "$patch_name" == *"a8xx"* ]] || [[ "$patch_name" == *"A8xx"* ]]; then
                if [[ "$TARGET_GPU" != "a8xx" ]]; then continue; fi
            fi
            log_info "Applying: $patch_name"
            if git apply --check "$patch" 2>/dev/null; then
                git apply "$patch"
                log_success "Applied: $patch_name"
            else
                log_warn "Could not apply: $patch_name"
            fi
        done
    fi
        log_success "All patches applied"
}

setup_subprojects() {
    log_info "Setting up subprojects via Meson wraps"
    cd "$MESA_DIR"
    mkdir -p subprojects/packagecache
    log_success "Subprojects ready"
}

create_cross_file() {
    log_info "Creating cross-compilation file"
    local ndk_bin="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    local ndk_sys="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
    [[ ! -d "$ndk_bin" ]] && { log_error "NDK not found: $ndk_bin"; exit 1; }
    local cver="$API_LEVEL"
    [[ ! -f "${ndk_bin}/aarch64-linux-android${cver}-clang" ]] && cver="35"
    [[ ! -f "${ndk_bin}/aarch64-linux-android${cver}-clang" ]] && cver="34"
    local c_args_list="'-D__ANDROID__', '-Wno-error', '-Wno-deprecated-declarations'"
    if [ -n "$CFLAGS_EXTRA" ]; then for flag in $CFLAGS_EXTRA; do c_args_list="$c_args_list, '$flag'"; done; fi
    local cpp_args_list="'-D__ANDROID__', '-Wno-error', '-Wno-deprecated-declarations'"
    if [ -n "$CXXFLAGS_EXTRA" ]; then for flag in $CXXFLAGS_EXTRA; do cpp_args_list="$cpp_args_list, '$flag'"; done; fi
    local link_args_list="'-static-libstdc++'"
    if [ -n "$LDFLAGS_EXTRA" ]; then for flag in $LDFLAGS_EXTRA; do link_args_list="$link_args_list, '$flag'"; done; fi
    cat > "${WORKDIR}/cross-aarch64.txt" << EOF
[binaries]
ar     = '${ndk_bin}/llvm-ar'
c      = ['ccache', '${ndk_bin}/aarch64-linux-android${cver}-clang', '--sysroot=${ndk_sys}']
cpp    = ['ccache', '${ndk_bin}/aarch64-linux-android${cver}-clang++', '--sysroot=${ndk_sys}']
c_ld   = 'lld'
cpp_ld = 'lld'
strip  = '${ndk_bin}/aarch64-linux-android-strip'
[host_machine]
system     = 'android'
cpu_family = 'aarch64'
cpu        = 'armv8'
endian     = 'little'
[built-in options]
c_args        = [$c_args_list]
cpp_args      = [$cpp_args_list]
c_link_args   = [$link_args_list]
cpp_link_args = [$link_args_list]
EOF
    log_success "Cross-compilation file created"
}

configure_build() {
    log_info "Configuring Mesa build"
    cd "$MESA_DIR"
    local buildtype="$BUILD_TYPE"    if [[ "$BUILD_VARIANT" == "debug" ]]; then buildtype="debug"; fi
    if [[ "$BUILD_VARIANT" == "profile" ]]; then buildtype="debugoptimized"; fi
    meson setup build \
        --cross-file "${WORKDIR}/cross-aarch64.txt" \
        -Dbuildtype="$buildtype" \
        -Dplatforms=android \
        -Dplatform-sdk-version="$API_LEVEL" \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dglx=disabled \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Dopengl=false \
        -Dgbm=disabled \
        -Dllvm=disabled \
        -Dlibunwind=disabled \
        -Dlmsensors=disabled \
        -Dzstd=disabled \
        -Dvalgrind=disabled \
        -Dbuild-tests=false \
        -Dwerror=false \
        -Ddefault_library=shared \
        --force-fallback-for=spirv-tools,spirv-headers \
        2>&1 | tee "${WORKDIR}/meson.log"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then log_error "Meson configuration failed"; exit 1; fi
    log_success "Build configured"
}

compile_driver() {
    log_info "Compiling Turnip driver"
    local cores=$(nproc 2>/dev/null || echo 4)
    ninja -C "${MESA_DIR}/build" -j"$cores" 2>&1 | tee "${WORKDIR}/ninja.log"
    local driver="${MESA_DIR}/build/src/freedreno/vulkan/libvulkan_freedreno.so"
    [[ ! -f "$driver" ]] && { log_error "Build failed: driver not found"; exit 1; }
    log_success "Compilation complete"
}

package_driver() {
    log_info "Packaging driver"
    local version=$(cat "${WORKDIR}/version.txt")
    local commit=$(cat "${WORKDIR}/commit.txt")
    local vulkan_version=$(get_vulkan_version)
    local build_date=$(date +'%Y-%m-%d')
    local driver_src="${MESA_DIR}/build/src/freedreno/vulkan/libvulkan_freedreno.so"
    local pkg_dir="${WORKDIR}/package"
    local name_suffix="${TARGET_GPU:1}"    local driver_name="vulkan.ad0${name_suffix}.so"
    mkdir -p "$pkg_dir"
    cp "$driver_src" "${pkg_dir}/${driver_name}"
    patchelf --set-soname "vulkan.adreno.so" "${pkg_dir}/${driver_name}"
    "${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
        "${pkg_dir}/${driver_name}" 2>/dev/null || true
    local driver_size=$(du -h "${pkg_dir}/${driver_name}" | cut -f1)
    local variant_suffix=""
    case "$BUILD_VARIANT" in
        optimized) variant_suffix="opt"     ;;
        autotuner) variant_suffix="at"      ;;
        vanilla)   variant_suffix="vanilla" ;;
        debug)     variant_suffix="debug"   ;;
        profile)   variant_suffix="profile" ;;
    esac
    local filename="turnip_${TARGET_GPU}_v${version}_${variant_suffix}_${build_date}"
    cat > "${pkg_dir}/meta.json" << EOF
{
  "schemaVersion": 1,
  "name": "Turnip ${TARGET_GPU} ${BUILD_VARIANT}",
  "description": "Compiled From Mesa Freedreno",
  "author": "BlueInstruction",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "${vulkan_version}",
  "minApi": 28,
  "libraryName": "${driver_name}"
}
EOF
    echo "$filename"        > "${WORKDIR}/filename.txt"
    echo "$vulkan_version"  > "${WORKDIR}/vulkan_version.txt"
    echo "$build_date"      > "${WORKDIR}/build_date.txt"
    cd "$pkg_dir"
    zip -9 "${WORKDIR}/${filename}.zip" "$driver_name" meta.json
    log_success "Package created: ${filename}.zip ($driver_size)"
}

print_summary() {
    local version=$(cat "${WORKDIR}/version.txt")
    local commit=$(cat "${WORKDIR}/commit.txt")
    local vulkan_version=$(cat "${WORKDIR}/vulkan_version.txt")
    local build_date=$(cat "${WORKDIR}/build_date.txt")
    echo ""
    log_info "Build Summary"
    echo "  Target GPU    : $TARGET_GPU"
    echo "  Mesa Version   : $version"
    echo "  Vulkan Version : $vulkan_version"
    echo "  Commit         : $commit"
    echo "  Build Date     : $build_date"
    echo "  Build Variant  : $BUILD_VARIANT"    echo "  Output         :"
    ls -lh "${WORKDIR}"/*.zip 2>/dev/null | awk '{print "    " $9 " (" $5 ")"}'
    echo ""
}

main() {
    log_info "Turnip Driver Builder"
    check_deps
    prepare_workdir
    clone_mesa
    apply_patches
    verify_injection_safety || exit 1
    setup_subprojects
    create_cross_file
    configure_build
    compile_driver
    package_driver
    print_summary
    log_success "Build completed successfully"
}

main "$@"
