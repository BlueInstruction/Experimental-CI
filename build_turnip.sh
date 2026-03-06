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
AUTOTUNER_REPO="https://gitlab.freedesktop.org/PixelyIon/mesa.git"
VULKAN_HEADERS_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"

MESA_SOURCE="${MESA_SOURCE:-main_branch}"
STAGING_BRANCH="${STAGING_BRANCH:-staging/26.0}"
CUSTOM_TAG="${CUSTOM_TAG:-}"
BUILD_TYPE="${BUILD_TYPE:-release}"
BUILD_VARIANT="${BUILD_VARIANT:-optimized}"
NDK_PATH="${NDK_PATH:-/opt/android-ndk}"
API_LEVEL="${API_LEVEL:-35}"
TARGET_GPU="${TARGET_GPU:-a7xx}"
ENABLE_PERF="${ENABLE_PERF:-false}"
MESA_LOCAL_PATH="${MESA_LOCAL_PATH:-}"
ENABLE_EXT_SPOOF="${ENABLE_EXT_SPOOF:-true}"
ENABLE_DECK_EMU="${ENABLE_DECK_EMU:-true}"
DECK_EMU_TARGET="${DECK_EMU_TARGET:-nvidia}"
ENABLE_TIMELINE_HACK="${ENABLE_TIMELINE_HACK:-true}"
ENABLE_UBWC_HACK="${ENABLE_UBWC_HACK:-true}"
APPLY_PATCH_SERIES="${APPLY_PATCH_SERIES:-true}"
CFLAGS_EXTRA="${CFLAGS_EXTRA:--O3 -march=armv8.2-a+fp16+rcpc+dotprod}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:--O3 -march=armv8.2-a+fp16+rcpc+dotprod}"
LDFLAGS_EXTRA="${LDFLAGS_EXTRA:--Wl,--gc-sections}"

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

update_vulkan_headers() {
    log_info "Updating Vulkan headers to latest version"
    local headers_dir="${WORKDIR}/vulkan-headers"
    git clone --depth=1 "$VULKAN_HEADERS_REPO" "$headers_dir" 2>/dev/null || {
        log_warn "Failed to clone Vulkan headers, using Mesa defaults"
        return 0
    }
    if [[ -d "${headers_dir}/include/vulkan" ]]; then
        cp -r "${headers_dir}/include/vulkan"\n'
    '   case 6: /* UBWC 6.0 */\n'
    '      device->ubwc_config.bank_swizzle_levels = 0x6;\n'
    '      device->ubwc_config.macrotile_mode = FDL_MACROTILE_8_CHANNEL;\n'
    '      break;\n'
)
pat = r'(case KGSL_UBWC_4_0:.*?break;\n)([ \t]*default:)'
m = re.search(pat, c, re.DOTALL)
if m:
    c = c[:m.start(2)] + inject + c[m.start(2):]
    with open(fp, 'w') as f:
        f.write(c)
    print('[OK] UBWC 5/6 cases inserted before default:')
else:
    print('[WARN] UBWC switch pattern not found, skipping')
PYEOF
        log_success "UBWC 5/6 support applied"
    else
        log_info "UBWC 5/6: already patched or file not found"
    fi

    # Mesa 26.x already ships proper a8xx device entries upstream
    # (FD830/0x44050000, Adreno 840/0xffff44050A31, X2-85/0xffff44070041).
    # The old injection used 'num_slices' which is NOT a parameter of
    # A6xxGPUInfo.__init__, causing TypeError when Mesa runs the script.
    # It also did a partial regex replace leaving orphaned Python syntax.
    log_info "A8xx: using upstream Mesa device table (no custom injection)"

    log_success "A8xx support applied"
}

apply_custom_debug_flags() {
    log_info "Adding custom TU_DEBUG flags: force_vrs, push_regs, ubwc_all, slc_pin, turbo, defrag, cp_prefetch, shfl, vgt_pref, unroll"

    local tu_util_h="${MESA_DIR}/src/freedreno/vulkan/tu_util.h"
    local tu_util_cc="${MESA_DIR}/src/freedreno/vulkan/tu_util.cc"
    local tu_device_cc="${MESA_DIR}/src/freedreno/vulkan/tu_device.cc"
    local tu_image_cc="${MESA_DIR}/src/freedreno/vulkan/tu_image.cc"
    local ir3_ra_c="${MESA_DIR}/src/freedreno/ir3/ir3_ra.c"
    local ir3_compiler_nir="${MESA_DIR}/src/freedreno/ir3/ir3_compiler_nir.c"

    [[ ! -f "$tu_util_h" ]] && { log_warn "tu_util.h not found, skipping custom flags"; return 0; }

    # ── Step 1: BITFIELD64 definitions in tu_util.h ──────────────────────
    python3 - "$tu_util_h" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()
if 'TU_DEBUG_FORCE_VRS' in c:
    print('[OK] tu_util.h already has custom flags'); sys.exit(0)
bits = list(map(int, re.findall(r'BITFIELD64_BIT\((\d+)\)', c)))
if not bits:
    print('[WARN] No BITFIELD64_BIT found'); sys.exit(0)
next_bit = max(bits) + 1
flags = [
    'TU_DEBUG_FORCE_VRS','TU_DEBUG_PUSH_REGS','TU_DEBUG_UBWC_ALL',
    'TU_DEBUG_SLC_PIN','TU_DEBUG_TURBO','TU_DEBUG_DEFRAG',
    'TU_DEBUG_CP_PREFETCH','TU_DEBUG_SHFL','TU_DEBUG_VGT_PREF',
    'TU_DEBUG_UNROLL',
]
lines = '\n'.join(f'   {f:<32} = BITFIELD64_BIT({next_bit + i}),' for i, f in enumerate(flags))
# Find last BITFIELD64_BIT line and append after it
all_m = list(re.finditer(r'   TU_DEBUG_\w+\s*=\s*BITFIELD64_BIT\(\d+\),?', c))
if all_m:
    last = all_m[-1]
    eol = c.find('\n', last.end())
    c = c[:eol+1] + lines + '\n' + c[eol+1:]
    with open(fp, 'w') as f: f.write(c)
    print(f'[OK] Added {len(flags)} custom TU_DEBUG flags starting at bit {next_bit}')
else:
    print('[WARN] Could not find enum insertion point in tu_util.h')
PYEOF

    # ── Step 2: debug name table in tu_util.cc ────────────────────────────
    python3 - "$tu_util_cc" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()
if 'force_vrs' in c:
    print('[OK] tu_util.cc already patched'); sys.exit(0)
new_entries = (
    '   { "force_vrs",   TU_DEBUG_FORCE_VRS   },\n'
    '   { "push_regs",   TU_DEBUG_PUSH_REGS   },\n'
    '   { "ubwc_all",    TU_DEBUG_UBWC_ALL    },\n'
    '   { "slc_pin",     TU_DEBUG_SLC_PIN     },\n'
    '   { "turbo",       TU_DEBUG_TURBO       },\n'
    '   { "defrag",      TU_DEBUG_DEFRAG      },\n'
    '   { "cp_prefetch", TU_DEBUG_CP_PREFETCH },\n'
    '   { "shfl",        TU_DEBUG_SHFL        },\n'
    '   { "vgt_pref",    TU_DEBUG_VGT_PREF    },\n'
    '   { "unroll",      TU_DEBUG_UNROLL      },\n'
)
all_m = list(re.finditer(r'\{\s*"[a-z_]+"\s*,\s*TU_DEBUG_\w+\s*\}', c))
if all_m:
    last = all_m[-1]
    eol = c.find('\n', last.end())
    c = c[:eol+1] + new_entries + c[eol+1:]
    with open(fp, 'w') as f: f.write(c)
    print('[OK] Added 10 custom entries to debug table in tu_util.cc')
else:
    print('[WARN] Debug table not found in tu_util.cc')
PYEOF

    # ── Step 3: turbo — sysfs perf governor (silent fail, no crash) ───────
    if [[ -f "$tu_device_cc" ]] && ! grep -q "tu_try_activate_turbo" "$tu_device_cc"; then
        python3 - "$tu_device_cc" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

turbo_func = """
/* TU_DEBUG_TURBO: attempt to lock GPU at max frequency via sysfs.
 * Silently ignored if process lacks root permission — no crash. */
static void
tu_try_activate_turbo(void)
{
   static const char * const min_paths[] = {
      "/sys/class/kgsl/kgsl-3d0/min_pwrlevel",
      "/sys/class/devfreq/kgsl-3d0/min_freq",
      NULL,
   };
   static const char * const gov_paths[] = {
      "/sys/class/kgsl/kgsl-3d0/devfreq/governor",
      "/sys/class/devfreq/kgsl-3d0/governor",
      NULL,
   };
   for (int i = 0; min_paths[i]; i++) {
      int fd = open(min_paths[i], O_WRONLY | O_CLOEXEC);
      if (fd >= 0) { (void)write(fd, "0", 1); close(fd); break; }
   }
   for (int i = 0; gov_paths[i]; i++) {
      int fd = open(gov_paths[i], O_WRONLY | O_CLOEXEC);
      if (fd >= 0) { (void)write(fd, "performance", 11); close(fd); break; }
   }
}
"""

turbo_call = """
   /* TU_DEBUG_TURBO: request max GPU performance at device creation */
   if (TU_DEBUG(TURBO))
      tu_try_activate_turbo();
"""

# Insert function before first static/VkResult function
m_func = re.search(r'\n(static |VkResult |void )', c)
if m_func and 'tu_try_activate_turbo' not in c:
    c = c[:m_func.start()+1] + turbo_func + '\n' + c[m_func.start()+1:]

# Insert call right after tu_physical_device_init succeeds
m_call = re.search(r'(result\s*=\s*tu_physical_device_init\([^;]+;\s*\n\s*if\s*\([^)]+\)[^{]*\{[^}]*\}\s*\n)', c, re.DOTALL)
if not m_call:
    # Simpler: find the line with tu_physical_device_init and inject after it
    m_call = re.search(r'(tu_physical_device_init\([^;]+;\s*\n)', c)
if m_call:
    c = c[:m_call.end()] + turbo_call + c[m_call.end():]

with open(fp, 'w') as f: f.write(c)
print('[OK] turbo mode injected into tu_device.cc')
PYEOF
        log_success "TU_DEBUG_TURBO implementation added"
    fi

    # ── Step 4: defrag — align large allocations to 64KB ──────────────────
    if [[ -f "$tu_device_cc" ]] && ! grep -q "TU_DEBUG_DEFRAG" "$tu_device_cc"; then
        python3 - "$tu_device_cc" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

defrag_code = """
   /* TU_DEBUG_DEFRAG: align large BO allocations to 64KB for
    * better memory contiguity and reduced fragmentation. */
   if (TU_DEBUG(DEFRAG) && size > (1u << 20))
      size = ALIGN(size, 64 * 1024);
"""

# Find tu_bo_init_new body — look for the first use of 'size' param
# after function signature to insert alignment before actual alloc
m = re.search(r'(VkResult\s+\w*bo_init_new\w*\s*\([^{]+\{)', c)
if m:
    body_start = m.end()
    # Find first statement inside body
    first_stmt = re.search(r'\n\s+\S', c[body_start:])
    if first_stmt:
        ins = body_start + first_stmt.start() + 1
        c = c[:ins] + defrag_code + c[ins:]
        with open(fp, 'w') as f: f.write(c)
        print('[OK] defrag alignment injected into tu_device.cc')
    else:
        with open(fp, 'w') as f: f.write(c)
        print('[WARN] defrag: body start not found')
else:
    with open(fp, 'w') as f: f.write(c)
    print('[WARN] defrag: bo_init_new not found, skipping')
PYEOF
        log_success "TU_DEBUG_DEFRAG implementation added"
    fi

    # ── Step 5: ubwc_all — force UBWC on color images ─────────────────────
    if [[ -f "$tu_image_cc" ]] && ! grep -q "TU_DEBUG_UBWC_ALL" "$tu_image_cc"; then
        python3 - "$tu_image_cc" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

ubwc_code = """
   
   if (TU_DEBUG(UBWC_ALL)) {
      if (!vk_format_is_depth_or_stencil(image->vk.format) &&
          !vk_format_is_compressed(image->vk.format) &&
          image->vk.format != VK_FORMAT_UNDEFINED) {
         
         for (unsigned _p = 0; _p < ARRAY_SIZE(image->layout); _p++)
            image->layout[_p].ubwc = true;
      }
   }
"""

# Find tu_image_init_layout or tu_image_init and inject before final return
m = re.search(r'VkResult\s+(tu_image_init|tu_image_create)[^{]*\{', c)
if m:
    func_start = m.end()
    # Find last return VK_SUCCESS in this function
    returns = list(re.finditer(r'return VK_SUCCESS;', c[func_start:]))
    if returns:
        last_ret = returns[-1]
        ins = func_start + last_ret.start()
        c = c[:ins] + ubwc_code + '\n   ' + c[ins:]
        with open(fp, 'w') as f: f.write(c)
        print('[OK] ubwc_all injected into tu_image.cc')
    else:
        print('[WARN] ubwc_all: no return point found')
        with open(fp, 'w') as f: f.write(c)
else:
    print('[WARN] ubwc_all: tu_image_init not found')
PYEOF
        log_success "TU_DEBUG_UBWC_ALL implementation added"
    fi

    # ── Step 6: push_regs — relax ir3 register pressure limit ─────────────
    if [[ -f "$ir3_ra_c" ]] && ! grep -q "ir3_ra_max_regs_override" "$ir3_ra_c"; then
        python3 - "$ir3_ra_c" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

helper = """
/* TU_DEBUG_PUSH_REGS: helper to double register limit for a7xx shaders.
 * Checked via getenv because ir3 has no access to tu_device. */
static inline unsigned
ir3_ra_max_regs_override(unsigned default_max)
{
   const char *dbg = getenv("TU_DEBUG");
   if (dbg && strstr(dbg, "push_regs"))
      return MIN2(default_max * 2u, 96u);
   return default_max;
}
"""

# Insert after last #include
includes = list(re.finditer(r'^#include\b.*', c, re.MULTILINE))
if includes:
    eol = c.find('\n', includes[-1].start())
    c = c[:eol+1] + helper + c[eol+1:]
    with open(fp, 'w') as f: f.write(c)
    print('[OK] push_regs helper added to ir3_ra.c')
else:
    print('[WARN] push_regs: no includes found in ir3_ra.c')
PYEOF
        log_success "TU_DEBUG_PUSH_REGS helper added"
    fi

    # ── Step 7: unroll — aggressive NIR loop unrolling ────────────────────
    if [[ -f "$ir3_compiler_nir" ]] && ! grep -q "TU_DEBUG.*unroll\|ir3_custom_unroll" "$ir3_compiler_nir"; then
        python3 - "$ir3_compiler_nir" << 'PYEOF'
import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

# Inject after nir_opt_loop_unroll call if it exists,
# otherwise after the last OPT() macro call with nir
unroll_code = """
   /* TU_DEBUG_UNROLL: aggressive loop unrolling for heavy shader workloads */
   {
      const char *_dbg = getenv("TU_DEBUG");
      if (_dbg && strstr(_dbg, "unroll"))
         NIR_PASS(progress, nir, nir_opt_loop_unroll);
   }
"""

m = re.search(r'(NIR_PASS[^;]+nir_opt_loop_unroll[^;]+;\s*\n)', c)
if not m:
    all_m = list(re.finditer(r'(NIR_PASS|OPT)\([^;]+;\s*\n', c))
    m = all_m[-1] if all_m else None
if m:
    c = c[:m.end()] + unroll_code + c[m.end():]
    with open(fp, 'w') as f: f.write(c)
    print('[OK] unroll pass injected into ir3_compiler_nir.c')
else:
    print('[WARN] unroll: no NIR pass insertion point found')
PYEOF
        log_success "TU_DEBUG_UNROLL implementation added"
    fi

    # ── Step 8: slc_pin / cp_prefetch / shfl / vgt_pref ──────────────────
    # These flags are DEFINED (so TU_DEBUG=slc_pin,... is valid without crash)
    # but have no userspace implementation — they require kernel/HW support.
    log_info "slc_pin / cp_prefetch / shfl / vgt_pref: flags registered (kernel-side implementation required)"

    log_success "All custom TU_DEBUG flags applied"
}

apply_patches() {
    log_info "Applying patches for $TARGET_GPU"
    cd "$MESA_DIR"
    if [[ "$BUILD_VARIANT" == "vanilla" ]]; then
        log_info "Vanilla build - skipping all patches"
        return 0
    fi
    if [[ "$APPLY_PATCH_SERIES" == "true" && -d "$PATCHES_DIR/series" ]]; then
        apply_patch_series "$PATCHES_DIR/series"
    else
        if [[ "$ENABLE_TIMELINE_HACK" == "true" ]]; then apply_timeline_semaphore_fix; fi
        if [[ "$ENABLE_UBWC_HACK" == "true" ]]; then true; fi
        apply_gralloc_ubwc_fix
        apply_custom_debug_flags
        if [[ "$ENABLE_DECK_EMU" == "true" ]]; then apply_deck_emu_support; fi
        if [[ "$ENABLE_EXT_SPOOF" == "true" ]]; then apply_vulkan_extensions_support; fi
        if [[ "$TARGET_GPU" == "a8xx" ]]; then
            apply_a8xx_device_support
        fi
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

# They use CMake and have no meson.build, which causes --force-fallback-for
# to fail at configure time with "subproject has no meson.build file".
# Mesa ships its own .wrap files for spirv-tools and spirv-headers;
# Meson will download the correct Meson-compatible tarballs automatically.
setup_subprojects() {
    log_info "Setting up subprojects via Meson wraps"
    cd "$MESA_DIR"
    mkdir -p subprojects/packagecache
    log_success "Subprojects ready (Meson wraps will resolve at configure time)"
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
    local buildtype="$BUILD_TYPE"
    if [[ "$BUILD_VARIANT" == "debug" ]]; then buildtype="debug"; fi
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
    local name_suffix="${TARGET_GPU:1}"
    local driver_name="vulkan.ad0${name_suffix}.so"
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
    echo "  Build Variant  : $BUILD_VARIANT"
    echo "  Output         :"
    ls -lh "${WORKDIR}"/*.zip 2>/dev/null | awk '{print "    " $9 " (" $5 ")"}'
    echo ""
}

main() {
    log_info "Turnip Driver Builder"
    check_deps
    prepare_workdir
    clone_mesa
    update_vulkan_headers
    apply_patches
    setup_subprojects
    create_cross_file
    configure_build
    compile_driver
    package_driver
    print_summary
    log_success "Build completed successfully"
}

main "$@"
