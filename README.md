# 🐉 Dragon Driver

Mesa Turnip patch framework for Android with multiple build variants.

## Variants

| Variant | Code | Description |
|---------|------|-------------|
| Tiger | `tiger` | Base stable with velocity |
| Tiger-Phoenix | `tiger-phoenix` | Tiger + enhanced wings |
| Falcon | `falcon` | Legacy device support (A6xx) |
| Shadow | `shadow` | Experimental features / autotune |
| Hawk | `hawk` | Maximum power / full patch set |

## Usage

### Local Build
```bash
# Build a single variant
bash scripts/build_mesa_android.sh tiger

# Build all variants
bash scripts/build_mesa_android.sh all
