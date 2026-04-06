# vkd3d-proton-wcp

Custom builds of [VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton) packaged as `.wcp` files for Winlator.
Built from upstream with performance patches for Android-based Windows emulation environments.

---

## Builds

| Build | Target | CPU Runtime | Format |
|---|---|---|---|
| `vkd3d-proton` | x86_64 | Box64 | `.wcp` |
| `vkd3d-proton-arm64ec` | ARM64EC + x86_64 hybrid | FEXCore + WowBox64 | `.wcp` |

---

## Installation

1. Download the `.wcp` from [Releases](../../releases)
2. Open Winlator → **Contents Manager**
3. Tap **+** → **Import from file** → select the `.wcp`
4. Open container settings → **DX Wrapper** → set to `DXVK + VKD3D`
5. Under **VKD3D** → select the imported build

   Entries appear as:
   ```
   3.0b-20260405
   3.0b-20260405-arm64ec
   ```
6. Tap **Apply**

---

## WCP Structure

```
build.wcp
├── profile.json
├── system32/
│   ├── d3d12.dll
│   └── d3d12core.dll
└── syswow64/
    ├── d3d12.dll
    └── d3d12core.dll
```
---

## Debugging

Enable verbose VKD3D logging:
```
VKD3D_DEBUG=warn
VKD3D_LOG_FILE=./vkd3d.log.txt
```

---

## Credits

- [HansKristian-Work/vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton) — upstream VKD3D-Proton
- [doitsujin/dxvk](https://github.com/doitsujin/dxvk) — DXVK / shared DXGI
- [ptitSeb/box64](https://github.com/ptitSeb/box64) — x86_64 CPU runtime
- [FEX-Emu/FEX](https://github.com/FEX-Emu/FEX) — ARM64EC CPU runtime
- [StevenMXZ/Winlator-Ludashi](https://github.com/StevenMXZ/Winlator-Ludashi) — Winlator fork
