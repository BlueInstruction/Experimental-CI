#!/usr/bin/env bash
set -e

VARIANT="$1"

# Clone Mesa
if [ ! -d mesa ]; then
    git clone https://gitlab.freedesktop.org/mesa/mesa.git
fi
cd mesa

# Apply variant-specific spells
bash ../scripts/apply_spells.sh "$VARIANT"

# Meson cross file (example)
cat <<EOF > ../android-cross.ini
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'llvm-ar'
strip = 'llvm-strip'
pkg-config = 'pkg-config'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

# Setup build
meson setup build-android \
    --cross-file ../android-cross.ini \
    -Dvulkan-drivers=freedreno \
    -Dgallium-drivers= \
    -Dplatforms=android

# Build
ninja -C build-android

# Package
mkdir -p ../driver_chamber
cp build-android/src/freedreno/vulkan/libvulkan_freedreno.so ../driver_chamber/vulkan.dragon.so
cd ..
zip -r "driver_chamber/${VARIANT}.zip" driver_chamber/vulkan.dragon.so
