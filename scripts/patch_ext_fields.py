import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

INJECT = """
   /* EXT_INJECT_APPLIED */
   ext->AMD_anti_lag = true;
   ext->AMD_device_coherent_memory = true;
   ext->AMD_memory_overallocation_behavior = true;
   ext->AMD_shader_core_properties = true;
   ext->AMD_shader_core_properties2 = true;
   ext->AMD_shader_info = true;
   ext->EXT_blend_operation_advanced = true;
   ext->EXT_buffer_device_address = true;
   ext->EXT_depth_bias_control = true;
   ext->EXT_depth_range_unrestricted = true;
   ext->EXT_device_fault = true;
   ext->EXT_discard_rectangles = true;
   ext->EXT_display_control = true;
   ext->EXT_fragment_density_map2 = true;
   ext->EXT_fragment_shader_interlock = true;
   ext->EXT_frame_boundary = true;
   ext->EXT_full_screen_exclusive = true;
   ext->EXT_image_compression_control = true;
   ext->EXT_image_compression_control_swapchain = true;
   ext->EXT_image_sliced_view_of_3d = true;
   ext->EXT_memory_priority = true;
   ext->EXT_mesh_shader = true;
   ext->EXT_opacity_micromap = true;
   ext->EXT_pageable_device_local_memory = true;
   ext->EXT_pipeline_library_group_handles = true;
   ext->EXT_pipeline_protected_access = true;
   ext->EXT_pipeline_robustness = true;
   ext->EXT_post_depth_coverage = true;
   ext->EXT_shader_atomic_float2 = true;
   ext->EXT_shader_object = true;
   ext->EXT_shader_subgroup_ballot = true;
   ext->EXT_shader_subgroup_vote = true;
   ext->EXT_shader_tile_image = true;
   ext->EXT_subpass_merge_feedback = true;
   ext->EXT_swapchain_maintenance1 = true;
   ext->EXT_ycbcr_2plane_444_formats = true;
   ext->EXT_ycbcr_image_arrays = true;
   ext->GOOGLE_user_type = true;
   ext->IMG_relaxed_line_rasterization = true;
   ext->INTEL_performance_query = true;
   ext->INTEL_shader_integer_functions2 = true;
   ext->KHR_compute_shader_derivatives = true;
   ext->KHR_cooperative_matrix = true;
   ext->KHR_depth_clamp_zero_one = true;
   ext->KHR_device_address_commands = true;
   ext->KHR_fragment_shader_barycentric = true;
   ext->KHR_maintenance10 = true;
   ext->KHR_maintenance7 = true;
   ext->KHR_maintenance8 = true;
   ext->KHR_maintenance9 = true;
   ext->KHR_performance_query = true;
   ext->KHR_pipeline_binary = true;
   ext->KHR_present_id = true;
   ext->KHR_present_id2 = true;
   ext->KHR_present_wait = true;
   ext->KHR_present_wait2 = true;
   ext->KHR_ray_tracing_pipeline = true;
   ext->KHR_ray_tracing_position_fetch = true;
   ext->KHR_robustness2 = true;
   ext->KHR_shader_maximal_reconvergence = true;
   ext->KHR_shader_quad_control = true;
   ext->KHR_swapchain_maintenance1 = true;
   ext->KHR_video_decode_av1 = true;
   ext->KHR_video_decode_h264 = true;
   ext->KHR_video_decode_h265 = true;
   ext->KHR_video_decode_queue = true;
   ext->KHR_video_encode_av1 = true;
   ext->KHR_video_encode_h264 = true;
   ext->KHR_video_encode_h265 = true;
   ext->KHR_video_encode_queue = true;
   ext->KHR_video_maintenance1 = true;
   ext->KHR_video_maintenance2 = true;
   ext->KHR_video_queue = true;
   ext->MESA_image_alignment_control = true;
   ext->NVX_image_view_handle = true;
   ext->NV_cooperative_matrix = true;
   ext->NV_device_diagnostic_checkpoints = true;
   ext->NV_device_diagnostics_config = true;
   ext->QCOM_filter_cubic_clamp = true;
   ext->QCOM_filter_cubic_weights = true;
   ext->QCOM_image_processing2 = true;
   ext->QCOM_render_pass_store_ops = true;
   ext->QCOM_render_pass_transform = true;
   ext->QCOM_tile_properties = true;
   ext->QCOM_ycbcr_degamma = true;
   ext->VALVE_descriptor_set_host_mapping = true;
   ext->EXT_zero_initialize_device_memory = true;
   ext->KHR_shader_bfloat16 = true;
   ext->KHR_unified_image_layouts = true;
   ext->QCOM_cooperative_matrix_conversion = true;
   ext->QCOM_data_graph_model = true;
   ext->QCOM_fragment_density_map_offset = true;
   ext->QCOM_image_processing = true;
   ext->QCOM_multiview_per_view_render_areas = true;
   ext->QCOM_multiview_per_view_viewports = true;
   ext->QCOM_render_pass_shader_resolve = true;
   ext->QCOM_rotated_copy_commands = true;
   ext->QCOM_tile_memory_heap = true;
   ext->QCOM_tile_shading = true;
   ext->VALVE_fragment_density_map_layered = true;
   ext->VALVE_shader_mixed_float_dot_product = true;
   ext->VALVE_video_encode_rgb_conversion = true;
   ext->AMDX_shader_enqueue = true;
   ext->ARM_render_pass_striped = true;
   ext->ARM_scheduling_controls = true;
   ext->ARM_shader_core_builtins = true;
   ext->ARM_shader_core_properties = true;
   ext->EXT_attachment_feedback_loop_dynamic_state = true;
   ext->EXT_attachment_feedback_loop_layout = true;
   ext->EXT_border_color_swizzle = true;
   ext->EXT_color_write_enable = true;
   ext->EXT_debug_marker = true;
   ext->EXT_depth_clamp_control = true;
   ext->EXT_descriptor_buffer = true;
   ext->EXT_device_address_binding_report = true;
   ext->EXT_dynamic_rendering_unused_attachments = true;
   ext->EXT_extended_dynamic_state3 = true;
   ext->EXT_external_memory_acquire_unmodified = true;
   ext->EXT_filter_cubic = true;
   ext->EXT_fragment_density_map = true;
   ext->EXT_graphics_pipeline_library = true;
   ext->EXT_host_image_copy = true;
   ext->EXT_host_query_reset = true;
   ext->EXT_image_2d_view_of_3d = true;
   ext->EXT_image_robustness = true;
   ext->EXT_image_view_min_lod = true;
   ext->EXT_index_type_uint8 = true;
   ext->EXT_layer_settings = true;
   ext->EXT_legacy_dithering = true;
   ext->EXT_line_rasterization = true;
   ext->EXT_load_store_op_none = true;
   ext->EXT_map_memory_placed = true;
   ext->EXT_memory_budget = true;
   ext->EXT_multi_draw = true;
   ext->EXT_multisampled_render_to_single_sampled = true;
   ext->EXT_mutable_descriptor_type = true;
   ext->EXT_nested_command_buffer = true;
   ext->EXT_non_seamless_cube_map = true;
   ext->EXT_primitives_generated_query = true;
   ext->EXT_provoking_vertex = true;
   ext->EXT_rasterization_order_attachment_access = true;
   ext->EXT_rgba10x6_formats = true;
   ext->EXT_robustness2 = true;
   ext->EXT_sample_locations = true;
   ext->EXT_sampler_filter_minmax = true;
   ext->EXT_scalar_block_layout = true;
   ext->EXT_separate_stencil_usage = true;
   ext->EXT_shader_atomic_float = true;
   ext->EXT_shader_demote_to_helper_invocation = true;
   ext->EXT_shader_image_atomic_int64 = true;
   ext->EXT_shader_module_identifier = true;
   ext->EXT_shader_replicated_composites = true;
   ext->EXT_shader_stencil_export = true;
   ext->EXT_shader_viewport_index_layer = true;
   ext->EXT_transform_feedback = true;
   ext->EXT_vertex_attribute_divisor = true;
   ext->EXT_vertex_input_dynamic_state = true;
   ext->EXT_video_encode_quantization_map = true;
   ext->KHR_acceleration_structure = true;
   ext->KHR_deferred_host_operations = true;
   ext->KHR_index_type_uint8 = true;
   ext->KHR_load_store_op_none = true;
   ext->KHR_map_memory2 = true;
   ext->KHR_ray_query = true;
   ext->KHR_ray_tracing_maintenance1 = true;
   ext->KHR_shader_expect_assume = true;
   ext->KHR_shader_float_controls2 = true;
   ext->KHR_shader_subgroup_rotate = true;
   ext->KHR_shader_subgroup_uniform_control_flow = true;
   ext->KHR_vertex_attribute_divisor = true;
   ext->NV_clip_space_w_scaling = true;
   ext->NV_compute_shader_derivatives = true;
   ext->NV_coverage_reduction_mode = true;
   ext->NV_dedicated_allocation_image_aliasing = true;
   ext->NV_fragment_coverage_to_color = true;
   ext->NV_fragment_shading_rate_enums = true;
   ext->NV_framebuffer_mixed_samples = true;
   ext->NV_inherited_viewport_scissor = true;
   ext->NV_linear_color_attachment = true;
   ext->NV_mesh_shader = true;
   ext->NV_raw_access_chains = true;
   ext->NV_representative_fragment_test = true;
   ext->NV_sample_mask_override_coverage = true;
   ext->NV_scissor_exclusive = true;
   ext->NV_shader_atomic_float16_vector = true;
   ext->NV_shader_image_footprint = true;
   ext->NV_shader_sm_builtins = true;
   ext->NV_shader_subgroup_partitioned = true;
   ext->NV_shading_rate_image = true;
   ext->NV_viewport_array2 = true;
   ext->NV_viewport_swizzle = true;
   ext->NV_win32_keyed_mutex = true;
"""

# Find get_device_extensions function and inject before its closing brace
m = re.search(r'(get_device_extensions\s*\([^)]*\)\s*\{)', c)
if not m:
    m = re.search(r'(tu_get_device_extensions\s*\([^)]*\)\s*\{)', c)

if m:
    # Find the matching closing brace
    depth = 0
    pos = m.start()
    start_brace = c.find('{', m.start())
    i = start_brace
    while i < len(c):
        if c[i] == '{': depth += 1
        elif c[i] == '}':
            depth -= 1
            if depth == 0:
                c = c[:i] + INJECT + c[i:]
                break
        i += 1
    with open(fp, 'w') as f: f.write(c)
    print(f'[OK] EXT injection: added {INJECT.count("ext->")} extensions to get_device_extensions')
else:
    # Fallback: flip false->true pattern
    n = 0
    for pat in [
        r'(\.(?:KHR|EXT|AMD|QCOM|NV|NVX|VALVE|GOOGLE|IMG|INTEL|MESA)_[A-Za-z0-9_]+\s*=\s*)false\b',
    ]:
        for mm in re.finditer(pat, c):
            c = c[:mm.start(2)] + 'true' + c[mm.end(2):]
            n += 1
    c += '\n/* EXT_INJECT_APPLIED */\n'
    with open(fp, 'w') as f: f.write(c)
    print(f'[OK] EXT fallback: flipped {n} bits')
