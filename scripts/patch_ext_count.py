import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

FORCE_EXTS = [
    "VK_KHR_unified_image_layouts",
    "VK_KHR_cooperative_matrix",
    "VK_KHR_shader_bfloat16",
    "VK_KHR_maintenance7",
    "VK_KHR_maintenance8",
    "VK_KHR_maintenance9",
    "VK_KHR_maintenance10",
    "VK_EXT_zero_initialize_device_memory",
    "VK_KHR_device_address_commands",
]

ext_entries = "\n".join(f'   {{"{e}", 1}},' for e in FORCE_EXTS)

inject_struct = f"""
/* FORCE_EXT_COUNT_PATCH */
static const struct {{ const char *name; uint32_t spec; }} _force_ext_list[] = {{
{ext_entries}
}};
static const int _force_ext_n = {len(FORCE_EXTS)};
static void _append_force_exts(uint32_t *cnt, VkExtensionProperties *props) {{
   for (int _i = 0; _i < _force_ext_n; _i++) {{
      bool _found = false;
      for (uint32_t _j = 0; props && _j < *cnt; _j++)
         if (!strcmp(props[_j].extensionName, _force_ext_list[_i].name)) {{ _found = true; break; }}
      if (!_found) {{
         if (props) {{
            __builtin_strncpy(props[*cnt].extensionName, _force_ext_list[_i].name, 255);
            props[*cnt].specVersion = _force_ext_list[_i].spec;
         }}
         (*cnt)++;
      }}
   }}
}}
"""

# Find the enumerate function — in Mesa 26.1 it's vk_physical_device_enumerate_extensions_2
# Find its return statement and inject our append before it
fn_pat = re.compile(r'vk_physical_device_enumerate_extensions_2\s*\([^{]+\{', re.DOTALL)
m = fn_pat.search(c)

if m:
    # Find matching closing brace
    depth, i = 0, c.find("{", m.start())
    end_brace = -1
    while i < len(c):
        if c[i] == "{": depth += 1
        elif c[i] == "}":
            depth -= 1
            if depth == 0:
                end_brace = i
                break
        i += 1

    if end_brace != -1:
        # Find last return before closing brace
        fn_body = c[m.start():end_brace]
        last_ret = fn_body.rfind("return")
        if last_ret != -1:
            ins = m.start() + last_ret
            c = c[:ins] + "   _append_force_exts(pPropertyCount, pProperties);\n" + c[ins:]

    # Add struct before function
    c = c[:m.start()] + inject_struct + c[m.start():]
    with open(fp, "w") as f: f.write(c)
    print(f"[OK] Force ext count patch applied ({len(FORCE_EXTS)} extensions)")
else:
    print("[WARN] vk_physical_device_enumerate_extensions_2 not found — skipping")
    # Still write marker
    c += "\n/* FORCE_EXT_COUNT_PATCH */\n"
    with open(fp, "w") as f: f.write(c)
