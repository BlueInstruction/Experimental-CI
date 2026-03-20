import sys, re
fp = sys.argv[1]
with open(fp) as f: c = f.read()

defines = (
    "\n#ifndef KGSL_UBWC_5_0\n"
    "#define KGSL_UBWC_5_0 5\n"
    "#endif\n"
    "#ifndef KGSL_UBWC_6_0\n"
    "#define KGSL_UBWC_6_0 6\n"
    "#endif\n"
)

if "#define KGSL_UBWC_5_0" not in c:
    first_include = c.find("#include")
    if first_include != -1:
        eol = c.find("\n", first_include)
        c = c[:eol+1] + defines + c[eol+1:]
        print("[OK] KGSL_UBWC_5_0/6_0 defines added")
    else:
        print("[WARN] No #include found, skipping defines")
        sys.exit(0)
else:
    print("[OK] KGSL_UBWC_5_0 already defined")

if "case KGSL_UBWC_5_0" in c or "case 5:" in c:
    with open(fp, "w") as f: f.write(c)
    print("[OK] UBWC 5/6 cases already present from patch series")
    sys.exit(0)

ubwc_pat = re.compile(r"case KGSL_UBWC_4_0.*?break;", re.DOTALL)
m4 = ubwc_pat.search(c)
if not m4:
    ubwc_pat = re.compile(r"case KGSL_UBWC_3_0.*?break;", re.DOTALL)
    m4 = ubwc_pat.search(c)

if not m4:
    with open(fp, "w") as f: f.write(c)
    print("[WARN] UBWC switch not found, defines only")
    sys.exit(0)

# Find the FULL lvalue expression that writes bank_swizzle_levels/macrotile_mode
# Pattern: device->ubwc_config.bank_swizzle_levels — must capture 'device->ubwc_config'
case_body = c[m4.start():m4.end()]

# Capture full expression: optional 'ptr->' prefix + struct name
# e.g. 'device->ubwc_config.bank_swizzle_levels' -> lval='device->ubwc_config'
# e.g. 'ubwc_config.bank_swizzle_levels'         -> lval='ubwc_config'
lval_pat = re.compile(
    r'((?:\w+->)?\w+)\.(bank_swizzle_levels|macrotile_mode)'
)
lval_m = lval_pat.search(case_body)

if not lval_m:
    # Fallback: any ptr->field or var.field assignment in the case body
    lval_m = re.search(r'((?:\w+->)?\w+)\.(\w+)\s*=', case_body)

if not lval_m:
    with open(fp, "w") as f: f.write(c)
    print("[WARN] ubwc lval not found in case body, defines only")
    sys.exit(0)

lval = lval_m.group(1)

default_m = re.search(r'[ \t]*default\s*:', c[m4.end():])
if not default_m:
    with open(fp, "w") as f: f.write(c)
    print("[WARN] default: not found, defines only")
    sys.exit(0)

ins = m4.end() + default_m.start()
inject = (
    "   case 5:\n"
    "   case 6:\n"
    f"      {lval}.bank_swizzle_levels = 0x6;\n"
    f"      {lval}.macrotile_mode = FDL_MACROTILE_8_CHANNEL;\n"
    "      break;\n"
)
c = c[:ins] + inject + c[ins:]
with open(fp, "w") as f: f.write(c)
print(f"[OK] UBWC 5/6 cases inserted (lval={lval}.)")
