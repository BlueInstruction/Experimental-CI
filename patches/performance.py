#!/usr/bin/env python3

import re
import os
import glob
import sys
import argparse
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
from typing import List, Tuple, Dict, Any
from dataclasses import dataclass, field

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class PatchResult:
    applied: int = 0
    skipped: int = 0
    errors: List[str] = field(default_factory=list)
    details: List[Dict[str, Any]] = field(default_factory=list)


CAPABILITY_PATCHES: List[Tuple[str, str, str]] = [
    (r'(data->HighestShaderModel\s*=\s*)[^;]+;', r'\1D3D_SHADER_MODEL_6_6;', 'shader_model_6_6'),
    (r'(info\.HighestShaderModel\s*=\s*)[^;]+;', r'\1D3D_SHADER_MODEL_6_6;', 'shader_model_6_6_info'),
    (r'(MaxSupportedFeatureLevel\s*=\s*)[^;]+;', r'\1D3D_FEATURE_LEVEL_12_2;', 'feature_level_12_2'),
    (r'(options1\.WaveOps\s*=\s*)[^;]+;', r'\1TRUE;', 'wave_ops'),
    (r'(options1\.WaveLaneCountMin\s*=\s*)[^;]+;', r'\g<1>32;', 'wave_lane_min'),
    (r'(options1\.WaveLaneCountMax\s*=\s*)[^;]+;', r'\g<1>64;', 'wave_lane_max'),
    (r'(options\.ResourceBindingTier\s*=\s*)[^;]+;', r'\1D3D12_RESOURCE_BINDING_TIER_3;', 'resource_binding_tier'),
    (r'(options\.TiledResourcesTier\s*=\s*)[^;]+;', r'\1D3D12_TILED_RESOURCES_TIER_3;', 'tiled_resources_tier'),
    (r'(options\.ResourceHeapTier\s*=\s*)[^;]+;', r'\1D3D12_RESOURCE_HEAP_TIER_2;', 'resource_heap_tier'),
    (r'(options\.DoublePrecisionFloatShaderOps\s*=\s*)[^;]+;', r'\1TRUE;', 'double_precision'),
    (r'(options1\.Int64ShaderOps\s*=\s*)[^;]+;', r'\1TRUE;', 'int64_ops'),
    (r'(options4\.Native16BitShaderOpsSupported\s*=\s*)[^;]+;', r'\1TRUE;', 'native_16bit'),
    (r'(options12\.EnhancedBarriersSupported\s*=\s*)[^;]+;', r'\1TRUE;', 'enhanced_barriers'),
    (r'(options2\.DepthBoundsTestSupported\s*=\s*)[^;]+;', r'\1TRUE;', 'depth_bounds'),
    (r'(options7\.MeshShaderTier\s*=\s*)[^;]+;', r'\1D3D12_MESH_SHADER_TIER_1;', 'mesh_shader'),
    (r'(options6\.VariableShadingRateTier\s*=\s*)[^;]+;', r'\1D3D12_VARIABLE_SHADING_RATE_TIER_2;', 'vrs'),
]

DESCRIPTOR_CACHE_PATCHES: List[Tuple[str, str, str]] = [
    (r'(struct d3d12_descriptor_heap\s*\{[^}]*)(VkDescriptorSet\s+vk_descriptor_sets;)',
     r'\1\2\n    uint64_t last_descriptor_hash;\n    bool descriptor_cache_valid;',
     'descriptor_heap_cache_fields'),
]

COMMAND_BATCH_PATCHES: List[Tuple[str, str, str]] = [
    (r'(struct d3d12_command_queue\s*\{[^}]*)(VkQueue\s+vk_queue;)',
     r'\1\2\n    uint32_t pending_submits;\n    uint32_t submit_threshold;',
     'command_queue_batch_fields'),
]

BARRIER_OPT_PATCHES: List[Tuple[str, str, str]] = [
    (r'(struct d3d12_command_list\s*\{[^}]*)(VkCommandBuffer\s+vk_command_buffer;)',
     r'\1\2\n    struct { uint32_t pending_barriers; VkPipelineStageFlags2 last_dst_stage; } barrier_state;',
     'command_list_barrier_state'),
]

PIPELINE_CACHE_PATCHES: List[Tuple[str, str, str]] = [
    (r'(struct d3d12_device\s*\{[^}]*)(VkDevice\s+vk_device;)',
     r'\1\2\n    struct { uint64_t *hashes; VkPipeline *pipelines; size_t count; size_t capacity; pthread_rwlock_t lock; } pipeline_cache;',
     'device_pipeline_cache'),
]

CPU_X86_64_PATCHES: List[Tuple[str, str, str]] = [
    (r'(vkd3d_cpu_supports_sse4_2\s*\(\s*\))', 'true', 'force_sse4_2'),
    (r'(vkd3d_cpu_supports_avx\s*\(\s*\))', 'true', 'force_avx'),
    (r'(vkd3d_cpu_supports_avx2\s*\(\s*\))', 'true', 'force_avx2'),
    (r'(vkd3d_cpu_supports_fma\s*\(\s*\))', 'true', 'force_fma'),
    (r'#define\s+VKD3D_ENABLE_AVX\s+\d+', '#define VKD3D_ENABLE_AVX 1', 'enable_avx'),
    (r'#define\s+VKD3D_ENABLE_AVX2\s+\d+', '#define VKD3D_ENABLE_AVX2 1', 'enable_avx2'),
    (r'#define\s+VKD3D_ENABLE_FMA\s+\d+', '#define VKD3D_ENABLE_FMA 1', 'enable_fma'),
    (r'#define\s+VKD3D_ENABLE_SSE4_2\s+\d+', '#define VKD3D_ENABLE_SSE4_2 1', 'enable_sse4_2'),
]

CPU_ARM64EC_PATCHES: List[Tuple[str, str, str]] = [
    (r'#define\s+VKD3D_ENABLE_AVX\s+\d+', '#define VKD3D_ENABLE_AVX 0', 'disable_avx'),
    (r'#define\s+VKD3D_ENABLE_AVX2\s+\d+', '#define VKD3D_ENABLE_AVX2 0', 'disable_avx2'),
    (r'#define\s+VKD3D_ENABLE_FMA\s+\d+', '#define VKD3D_ENABLE_FMA 0', 'disable_fma'),
    (r'#define\s+VKD3D_ENABLE_SSE4_2\s+\d+', '#define VKD3D_ENABLE_SSE4_2 0', 'disable_sse4_2'),
    (r'#define\s+VKD3D_ENABLE_SSE\s+\d+', '#define VKD3D_ENABLE_SSE 0', 'disable_sse'),
    (r'(vkd3d_cpu_supports_sse4_2\s*\(\s*\))', 'false', 'disable_sse4_2_check'),
    (r'(vkd3d_cpu_supports_avx\s*\(\s*\))', 'false', 'disable_avx_check'),
    (r'(vkd3d_cpu_supports_avx2\s*\(\s*\))', 'false', 'disable_avx2_check'),
    (r'(vkd3d_cpu_supports_fma\s*\(\s*\))', 'false', 'disable_fma_check'),
]

PERFORMANCE_PATCHES: List[Tuple[str, str, str]] = [
    (r'#define\s+VKD3D_DEBUG\s+1', '#define VKD3D_DEBUG 0', 'disable_debug'),
    (r'#define\s+VKD3D_PROFILING\s+1', '#define VKD3D_PROFILING 0', 'disable_profiling'),
]

TURNIP_PATCHES: List[Tuple[str, str, str]] = [
    (r'(maxSets\s*=\s*)\d+', r'\g<1>16384', 'increase_descriptor_pool'),
]


class VKD3DPatcher:
    def __init__(self, arch: str = 'x86_64', dry_run: bool = False):
        self.arch = arch
        self.dry_run = dry_run
        self.result = PatchResult()
        self._lock = Lock()

    def _apply_patches_to_file(self, filepath: str, patches: List[Tuple[str, str, str]]) -> Tuple[int, int, List[str], List[Dict]]:
        local_applied = 0
        local_skipped = 0
        local_errors = []
        local_details = []

        if not os.path.exists(filepath):
            return local_applied, local_skipped, local_errors, local_details

        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            local_errors.append(f'read error {filepath}: {e}')
            return local_applied, local_skipped, local_errors, local_details

        original = content
        file_changes = []

        for pattern, replacement, name in patches:
            try:
                matches = len(re.findall(pattern, content, re.MULTILINE | re.DOTALL))
                if matches > 0:
                    if not self.dry_run:
                        content = re.sub(pattern, replacement, content, flags=re.MULTILINE | re.DOTALL)
                    local_applied += matches
                    file_changes.append({'name': name, 'matches': matches})
                else:
                    local_skipped += 1
            except re.error as e:
                local_errors.append(f'regex error in {filepath}: {e}')

        if content != original and not self.dry_run:
            try:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
            except Exception as e:
                local_errors.append(f'write error {filepath}: {e}')

        if file_changes:
            local_details.append({'file': os.path.basename(filepath), 'changes': file_changes})

        return local_applied, local_skipped, local_errors, local_details

    def apply_all(self, src_dir: str) -> int:
        logger.info(f'source: {src_dir}')
        logger.info(f'arch: {self.arch}')
        logger.info(f'mode: {"dry-run" if self.dry_run else "apply"}')

        device_files = glob.glob(os.path.join(src_dir, 'libs/vkd3d/*.[ch]'))
        if not device_files:
            device_files = glob.glob(os.path.join(src_dir, 'src/**/*.[ch]'), recursive=True)

        all_files = [f for f in glob.glob(os.path.join(src_dir, '**/*.[ch]'), recursive=True)
                     if 'tests' not in f and 'demos' not in f]

        logger.info(f'device files: {len(device_files)}')
        logger.info(f'total files: {len(all_files)}')

        tasks = []

        for f in device_files:
            tasks.append((f, CAPABILITY_PATCHES))
            tasks.append((f, DESCRIPTOR_CACHE_PATCHES))
            tasks.append((f, COMMAND_BATCH_PATCHES))
            tasks.append((f, BARRIER_OPT_PATCHES))
            tasks.append((f, PIPELINE_CACHE_PATCHES))
            tasks.append((f, TURNIP_PATCHES))

        if self.arch == 'x86_64':
            for f in all_files:
                tasks.append((f, CPU_X86_64_PATCHES))
        else:
            for f in all_files:
                tasks.append((f, CPU_ARM64EC_PATCHES))

        for f in all_files:
            tasks.append((f, PERFORMANCE_PATCHES))

        max_workers = os.cpu_count() or 4
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(self._apply_patches_to_file, path, patches) for path, patches in tasks]
            for future in as_completed(futures):
                applied, skipped, errors, details = future.result()
                with self._lock:
                    self.result.applied += applied
                    self.result.skipped += skipped
                    self.result.errors.extend(errors)
                    self.result.details.extend(details)

        logger.info(f'applied: {self.result.applied}')
        logger.info(f'skipped: {self.result.skipped}')
        logger.info(f'errors: {len(self.result.errors)}')

        return 1 if self.result.errors else 0

    def generate_report(self, output_path: str) -> None:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(f'arch: {self.arch}\n')
            f.write(f'applied: {self.result.applied}\n')
            f.write(f'skipped: {self.result.skipped}\n')
            f.write(f'errors: {len(self.result.errors)}\n\n')

            if self.result.details:
                f.write('changes:\n')
                for detail in self.result.details:
                    f.write(f'  {detail["file"]}:\n')
                    for change in detail['changes']:
                        f.write(f'    {change["name"]}: {change["matches"]}\n')

            if self.result.errors:
                f.write('\nerrors:\n')
                for e in self.result.errors:
                    f.write(f'  {e}\n')

        logger.info(f'report: {output_path}')


def main():
    parser = argparse.ArgumentParser(description='vkd3d-proton performance patcher')
    parser.add_argument('src_dir', help='vkd3d-proton source directory')
    parser.add_argument('--arch', choices=['x86_64', 'arm64ec'], default='x86_64')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--report', action='store_true')

    args = parser.parse_args()

    if not os.path.isdir(args.src_dir):
        logger.error(f'directory not found: {args.src_dir}')
        sys.exit(1)

    patcher = VKD3DPatcher(args.arch, args.dry_run)
    result = patcher.apply_all(args.src_dir)

    if args.report:
        patcher.generate_report('patch-report.txt')

    sys.exit(result)


if __name__ == '__main__':
    main()
