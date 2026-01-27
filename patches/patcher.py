#!/usr/bin/env python3
"""
VKD3D-Proton Performance Patcher
"""
import re
import os
import glob
import sys
import argparse
import logging
import json
from typing import List, Tuple, Dict, Any, Optional
from dataclasses import dataclass, field
from enum import Enum

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


class PatchProfile(Enum):
    STANDARD = "standard"
    UE5_OPTIMIZED = "ue5"
    MAXIMUM = "maximum"


@dataclass
class PatchResult:
    applied: int = 0
    skipped: int = 0
    errors: List[str] = field(default_factory=list)
    details: List[Dict[str, Any]] = field(default_factory=list)


def make_assignment_pattern(var_path: str) -> str:
    escaped = re.escape(var_path)
    return rf'(?<![=!<>])(\b{escaped}\s*=\s*)(?![=])([^;]+);'


STEAM_DECK_GPU = {
    'vendor_id': '0x1002',
    'device_id': '0x163f',
    'device_desc': 'AMD Custom GPU 0405',
    'shared_memory': '16384',
}

SHADER_MODEL_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('data->HighestShaderModel'), r'\g<1>D3D_SHADER_MODEL_6_9;', 'shader_model_6_9'),
    (make_assignment_pattern('info.HighestShaderModel'), r'\g<1>D3D_SHADER_MODEL_6_9;', 'shader_model_6_9_info'),
    (make_assignment_pattern('MaxSupportedFeatureLevel'), r'\g<1>D3D_FEATURE_LEVEL_12_2;', 'feature_level_12_2'),
]

WAVE_OPERATIONS_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options1.WaveOps'), r'\g<1>TRUE;', 'wave_ops'),
    (make_assignment_pattern('options1.WaveLaneCountMin'), r'\g<1>32;', 'wave_lane_min'),
    (make_assignment_pattern('options1.WaveLaneCountMax'), r'\g<1>128;', 'wave_lane_max'),
    (make_assignment_pattern('options9.WaveMMATier'), r'\g<1>D3D12_WAVE_MMA_TIER_1_0;', 'wave_mma'),
]

RESOURCE_BINDING_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options.ResourceBindingTier'), r'\g<1>D3D12_RESOURCE_BINDING_TIER_3;', 'resource_binding_tier'),
    (make_assignment_pattern('options.TiledResourcesTier'), r'\g<1>D3D12_TILED_RESOURCES_TIER_4;', 'tiled_resources_tier'),
    (make_assignment_pattern('options.ResourceHeapTier'), r'\g<1>D3D12_RESOURCE_HEAP_TIER_2;', 'resource_heap_tier'),
    (make_assignment_pattern('options19.MaxSamplerDescriptorHeapSize'), r'\g<1>4096;', 'max_sampler_heap'),
    (make_assignment_pattern('options19.MaxViewDescriptorHeapSize'), r'\g<1>1000000;', 'max_view_heap'),
]

SHADER_OPERATIONS_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options.DoublePrecisionFloatShaderOps'), r'\g<1>TRUE;', 'double_precision'),
    (make_assignment_pattern('options1.Int64ShaderOps'), r'\g<1>TRUE;', 'int64_ops'),
    (make_assignment_pattern('options4.Native16BitShaderOpsSupported'), r'\g<1>TRUE;', 'native_16bit'),
    (make_assignment_pattern('options9.AtomicInt64OnTypedResourceSupported'), r'\g<1>TRUE;', 'atomic64_typed'),
    (make_assignment_pattern('options9.AtomicInt64OnGroupSharedSupported'), r'\g<1>TRUE;', 'atomic64_shared'),
    (make_assignment_pattern('options11.AtomicInt64OnDescriptorHeapResourceSupported'), r'\g<1>TRUE;', 'atomic64_heap'),
]

NANITE_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options7.MeshShaderTier'), r'\g<1>D3D12_MESH_SHADER_TIER_1;', 'mesh_shader'),
    (make_assignment_pattern('options9.MeshShaderPipelineStatsSupported'), r'\g<1>TRUE;', 'mesh_pipeline_stats'),
    (make_assignment_pattern('options9.MeshShaderSupportsFullRangeRenderTargetArrayIndex'), r'\g<1>TRUE;', 'mesh_full_range_rt'),
    (make_assignment_pattern('options9.DerivativesInMeshAndAmplificationShadersSupported'), r'\g<1>TRUE;', 'mesh_derivatives'),
    (make_assignment_pattern('options10.MeshShaderPerPrimitiveShadingRateSupported'), r'\g<1>TRUE;', 'mesh_per_primitive_vrs'),
    (make_assignment_pattern('options21.ExecuteIndirectTier'), r'\g<1>D3D12_EXECUTE_INDIRECT_TIER_1_1;', 'execute_indirect'),
    (make_assignment_pattern('options21.WorkGraphsTier'), r'\g<1>D3D12_WORK_GRAPHS_TIER_1_0;', 'work_graphs'),
    (make_assignment_pattern('options12.EnhancedBarriersSupported'), r'\g<1>TRUE;', 'enhanced_barriers'),
    (make_assignment_pattern('options20.ComputeOnlyWriteWatchSupported'), r'\g<1>TRUE;', 'compute_write_watch'),
]

LUMEN_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options5.RaytracingTier'), r'\g<1>D3D12_RAYTRACING_TIER_1_1;', 'raytracing_tier'),
    (make_assignment_pattern('options5.RenderPassesTier'), r'\g<1>D3D12_RENDER_PASS_TIER_2;', 'render_passes'),
    (make_assignment_pattern('options6.VariableShadingRateTier'), r'\g<1>D3D12_VARIABLE_SHADING_RATE_TIER_2;', 'vrs_tier'),
    (make_assignment_pattern('options6.ShadingRateImageTileSize'), r'\g<1>8;', 'vrs_tile_8'),
    (make_assignment_pattern('options6.BackgroundProcessingSupported'), r'\g<1>TRUE;', 'background_processing'),
    (make_assignment_pattern('options10.VariableRateShadingSumCombinerSupported'), r'\g<1>TRUE;', 'vrs_sum_combiner'),
]

VIRTUAL_SHADOW_MAPS_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options7.SamplerFeedbackTier'), r'\g<1>D3D12_SAMPLER_FEEDBACK_TIER_1_0;', 'sampler_feedback'),
    (make_assignment_pattern('options2.DepthBoundsTestSupported'), r'\g<1>TRUE;', 'depth_bounds'),
    (make_assignment_pattern('options14.AdvancedTextureOpsSupported'), r'\g<1>TRUE;', 'advanced_texture_ops'),
    (make_assignment_pattern('options14.WriteableMSAATexturesSupported'), r'\g<1>TRUE;', 'writeable_msaa'),
]

TEXTURE_STREAMING_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options8.UnalignedBlockTexturesSupported'), r'\g<1>TRUE;', 'unaligned_textures'),
    (make_assignment_pattern('options13.UnrestrictedBufferTextureCopyPitchSupported'), r'\g<1>TRUE;', 'unrestricted_copy'),
    (make_assignment_pattern('options13.TextureCopyBetweenDimensionsSupported'), r'\g<1>TRUE;', 'texture_copy_dims'),
    (make_assignment_pattern('options16.GPUUploadHeapSupported'), r'\g<1>TRUE;', 'gpu_upload_heap'),
]

RENDERING_FEATURES_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('options13.UnrestrictedVertexElementAlignmentSupported'), r'\g<1>TRUE;', 'unrestricted_vertex'),
    (make_assignment_pattern('options13.InvertedViewportHeightFlipsYSupported'), r'\g<1>TRUE;', 'inverted_viewport_y'),
    (make_assignment_pattern('options13.InvertedViewportDepthFlipsZSupported'), r'\g<1>TRUE;', 'inverted_viewport_z'),
    (make_assignment_pattern('options13.AlphaBlendFactorSupported'), r'\g<1>TRUE;', 'alpha_blend'),
    (make_assignment_pattern('options15.TriangleFanSupported'), r'\g<1>TRUE;', 'triangle_fan'),
    (make_assignment_pattern('options15.DynamicIndexBufferStripCutSupported'), r'\g<1>TRUE;', 'dynamic_strip_cut'),
    (make_assignment_pattern('options19.RasterizerDesc2Supported'), r'\g<1>TRUE;', 'rasterizer_desc2'),
    (make_assignment_pattern('options19.NarrowQuadrilateralLinesSupported'), r'\g<1>TRUE;', 'narrow_quad_lines'),
]

GPU_SPOOF_PATCHES: List[Tuple[str, str, str]] = [
    (make_assignment_pattern('adapter_id.vendor_id'), rf'\g<1>{STEAM_DECK_GPU["vendor_id"]};', 'vendor_id'),
    (make_assignment_pattern('adapter_id.device_id'), rf'\g<1>{STEAM_DECK_GPU["device_id"]};', 'device_id'),
    (r'(VendorId\s*=\s*)[^;]+;', rf'\g<1>{STEAM_DECK_GPU["vendor_id"]};', 'dxgi_vendor'),
    (r'(DeviceId\s*=\s*)[^;]+;', rf'\g<1>{STEAM_DECK_GPU["device_id"]};', 'dxgi_device'),
]

PERFORMANCE_PATCHES: List[Tuple[str, str, str]] = [
    (r'#define\s+VKD3D_DEBUG\s+1', '#define VKD3D_DEBUG 0', 'disable_debug'),
    (r'#define\s+VKD3D_PROFILING\s+1', '#define VKD3D_PROFILING 0', 'disable_profiling'),
    (r'#define\s+VKD3D_SHADER_DEBUG\s+1', '#define VKD3D_SHADER_DEBUG 0', 'disable_shader_debug'),
]

CPU_X86_64_PATCHES: List[Tuple[str, str, str]] = [
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
    (r'#define\s+VKD3D_ENABLE_NEON\s+\d+', '#define VKD3D_ENABLE_NEON 1', 'enable_neon'),
]


class VKD3DPatcher:
    CAPABILITY_FILES = ['device.c']
    EXCLUDED_DIRS = ['tests', 'demos', 'include']

    def __init__(
        self,
        arch: str = 'x86_64',
        profile: PatchProfile = PatchProfile.UE5_OPTIMIZED,
        dry_run: bool = False,
        gpu_spoof: bool = True
    ):
        self.arch = arch
        self.profile = profile
        self.dry_run = dry_run
        self.gpu_spoof = gpu_spoof
        self.result = PatchResult()

    def _get_patches_for_profile(self) -> List[List[Tuple[str, str, str]]]:
        base_patches = [
            SHADER_MODEL_PATCHES,
            WAVE_OPERATIONS_PATCHES,
            RESOURCE_BINDING_PATCHES,
            SHADER_OPERATIONS_PATCHES,
        ]

        if self.profile == PatchProfile.STANDARD:
            return base_patches

        ue5_patches = [
            NANITE_PATCHES,
            LUMEN_PATCHES,
            VIRTUAL_SHADOW_MAPS_PATCHES,
            TEXTURE_STREAMING_PATCHES,
        ]

        if self.profile == PatchProfile.UE5_OPTIMIZED:
            return base_patches + ue5_patches

        if self.profile == PatchProfile.MAXIMUM:
            return base_patches + ue5_patches + [RENDERING_FEATURES_PATCHES]

        return base_patches

    def _apply_patches_to_file(
        self,
        filepath: str,
        patches: List[Tuple[str, str, str]]
    ) -> Tuple[int, int, List[str], List[Dict]]:
        local_applied = 0
        local_skipped = 0
        local_errors: List[str] = []
        local_details: List[Dict] = []

        if not os.path.exists(filepath):
            return local_applied, local_skipped, local_errors, local_details

        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            local_errors.append(f'read error {filepath}: {e}')
            return local_applied, local_skipped, local_errors, local_details

        original = content
        file_changes: List[Dict[str, Any]] = []

        for pattern, replacement, name in patches:
            try:
                regex = re.compile(pattern, re.MULTILINE)
                matches = len(regex.findall(content))
                if matches > 0:
                    if not self.dry_run:
                        content = regex.sub(replacement, content)
                    local_applied += matches
                    file_changes.append({'name': name, 'matches': matches})
                else:
                    local_skipped += 1
            except re.error as e:
                local_errors.append(f'regex error in {filepath} ({name}): {e}')

        if content != original and not self.dry_run:
            try:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
            except Exception as e:
                local_errors.append(f'write error {filepath}: {e}')

        if file_changes:
            local_details.append({'file': os.path.basename(filepath), 'changes': file_changes})

        return local_applied, local_skipped, local_errors, local_details

    def _find_vkd3d_dir(self, src_dir: str) -> str:
        vkd3d_dir = os.path.join(src_dir, 'libs', 'vkd3d')
        if os.path.isdir(vkd3d_dir):
            return vkd3d_dir
        return src_dir

    def _accumulate_result(self, applied: int, skipped: int, errors: List[str], details: List[Dict]):
        self.result.applied += applied
        self.result.skipped += skipped
        self.result.errors.extend(errors)
        self.result.details.extend(details)

    def apply_all(self, src_dir: str) -> int:
        logger.info(f'source: {src_dir}')
        logger.info(f'arch: {self.arch}')
        logger.info(f'profile: {self.profile.value}')
        logger.info(f'gpu_spoof: {self.gpu_spoof}')
        logger.info(f'mode: {"dry-run" if self.dry_run else "apply"}')

        vkd3d_dir = self._find_vkd3d_dir(src_dir)

        capability_files = []
        for cap_file in self.CAPABILITY_FILES:
            found = glob.glob(os.path.join(vkd3d_dir, '**', cap_file), recursive=True)
            capability_files.extend([f for f in found if not any(ex in f for ex in self.EXCLUDED_DIRS)])

        logger.info(f'capability files: {len(capability_files)}')

        patch_groups = self._get_patches_for_profile()

        for f in capability_files:
            for patches in patch_groups:
                self._accumulate_result(*self._apply_patches_to_file(f, patches))

            if self.gpu_spoof:
                self._accumulate_result(*self._apply_patches_to_file(f, GPU_SPOOF_PATCHES))

        all_c_files = glob.glob(os.path.join(src_dir, '**', '*.[ch]'), recursive=True)
        all_c_files = [f for f in all_c_files if not any(ex in f for ex in self.EXCLUDED_DIRS)]

        cpu_patches = CPU_X86_64_PATCHES if self.arch == 'x86_64' else CPU_ARM64EC_PATCHES

        for f in all_c_files:
            self._accumulate_result(*self._apply_patches_to_file(f, cpu_patches))
            self._accumulate_result(*self._apply_patches_to_file(f, PERFORMANCE_PATCHES))

        logger.info(f'applied: {self.result.applied}')
        logger.info(f'skipped: {self.result.skipped}')
        logger.info(f'errors: {len(self.result.errors)}')

        if self.result.errors:
            for err in self.result.errors[:10]:
                logger.error(err)

        return 1 if self.result.errors else 0

    def generate_report(self, output_path: str) -> None:
        report = {
            'arch': self.arch,
            'profile': self.profile.value,
            'gpu_spoof': 'Steam Deck Van Gogh' if self.gpu_spoof else 'disabled',
            'shader_model': '6.9',
            'feature_level': '12_2',
            'ue5_features': {
                'nanite': self.profile in [PatchProfile.UE5_OPTIMIZED, PatchProfile.MAXIMUM],
                'lumen': self.profile in [PatchProfile.UE5_OPTIMIZED, PatchProfile.MAXIMUM],
                'virtual_shadow_maps': self.profile in [PatchProfile.UE5_OPTIMIZED, PatchProfile.MAXIMUM],
                'mesh_shaders': True,
                'raytracing': True,
                'vrs': True,
                'work_graphs': True,
            },
            'stats': {
                'applied': self.result.applied,
                'skipped': self.result.skipped,
                'errors': len(self.result.errors),
            },
            'details': self.result.details,
            'errors': self.result.errors,
        }

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2)

        logger.info(f'report: {output_path}')

        with open(output_path.replace('.json', '.txt'), 'w', encoding='utf-8') as f:
            f.write('VKD3D-Proton UE5.5 Optimized Build\n')
            f.write('=' * 40 + '\n\n')
            f.write(f'Architecture: {self.arch}\n')
            f.write(f'Profile: {self.profile.value}\n')
            f.write(f'GPU Spoof: Steam Deck Van Gogh (0x163f)\n')
            f.write(f'Shader Model: 6.9\n')
            f.write(f'Feature Level: 12_2\n\n')
            f.write('UE5.5 Features:\n')
            f.write('  - Nanite (Mesh Shaders + Execute Indirect)\n')
            f.write('  - Lumen (Raytracing Tier 1.1 + VRS Tier 2)\n')
            f.write('  - Virtual Shadow Maps (Sampler Feedback)\n')
            f.write('  - Virtual Textures (Tiled Resources Tier 4)\n')
            f.write('  - Work Graphs Tier 1.0\n')
            f.write('  - Enhanced Barriers\n\n')
            f.write(f'Patches Applied: {self.result.applied}\n')
            f.write(f'Patches Skipped: {self.result.skipped}\n')
            f.write(f'Errors: {len(self.result.errors)}\n')


def main() -> None:
    parser = argparse.ArgumentParser(
        description='VKD3D-Proton Performance Patcher - UE5.5 Optimized',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Profiles:
  standard  - Basic D3D12 features
  ue5       - Optimized for Unreal Engine 5.5 (Nanite, Lumen, VSM)
  maximum   - All features enabled

Examples:
  %(prog)s /path/to/vkd3d --profile ue5 --arch arm64ec
  %(prog)s /path/to/vkd3d --profile maximum --no-gpu-spoof
        '''
    )
    parser.add_argument('src_dir', help='vkd3d-proton source directory')
    parser.add_argument('--arch', choices=['x86_64', 'arm64ec'], default='x86_64')
    parser.add_argument('--profile', choices=['standard', 'ue5', 'maximum'], default='ue5')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--no-gpu-spoof', action='store_true')
    parser.add_argument('--report', action='store_true')

    args = parser.parse_args()

    if not os.path.isdir(args.src_dir):
        logger.error(f'directory not found: {args.src_dir}')
        sys.exit(1)

    profile_map = {
        'standard': PatchProfile.STANDARD,
        'ue5': PatchProfile.UE5_OPTIMIZED,
        'maximum': PatchProfile.MAXIMUM,
    }

    patcher = VKD3DPatcher(
        arch=args.arch,
        profile=profile_map[args.profile],
        dry_run=args.dry_run,
        gpu_spoof=not args.no_gpu_spoof
    )

    result = patcher.apply_all(args.src_dir)

    if args.report:
        patcher.generate_report('patch-report.json')

    sys.exit(result)


if __name__ == '__main__':
    main()
