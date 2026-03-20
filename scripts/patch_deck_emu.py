import sys, re
fp, vendor_id, device_id, driver_version, device_name = sys.argv[1:6]
with open(fp) as f: c = f.read()

turbo_init = """
#include <fcntl.h>
#include <unistd.h>
/* DECK_EMU_PERF_INIT */
static void
tu_deck_perf_init(void)
{
   static const char * const pwrlevel_paths[] = {
      "/sys/class/kgsl/kgsl-3d0/min_pwrlevel",
      "/sys/class/devfreq/kgsl-3d0/min_freq",
      NULL,
   };
   static const char * const governor_paths[] = {
      "/sys/class/kgsl/kgsl-3d0/devfreq/governor",
      "/sys/class/devfreq/kgsl-3d0/governor",
      NULL,
   };
   for (int i = 0; pwrlevel_paths[i]; i++) {
      int fd = open(pwrlevel_paths[i], O_WRONLY | O_CLOEXEC);
      if (fd >= 0) { (void)write(fd, "0", 1); close(fd); break; }
   }
   for (int i = 0; governor_paths[i]; i++) {
      int fd = open(governor_paths[i], O_WRONLY | O_CLOEXEC);
      if (fd >= 0) { (void)write(fd, "performance", 11); close(fd); break; }
   }
}
"""

spoof_code = f"""
   /* DECK_EMU */
   if (getenv("TU_DECK_EMU")) {{
      props->vendorID      = {vendor_id};
      props->deviceID      = {device_id};
      props->driverVersion = {driver_version};
      snprintf(props->deviceName, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE, "{device_name}");
   }}
"""

perf_call = """
   /* DECK_EMU_PERF */
   tu_deck_perf_init();
"""

m = re.search(r'(tu_GetPhysicalDeviceProperties2?\s*\([^{]*\{)', c)
if not m:
    m = re.search(r'(vkGetPhysicalDeviceProperties2?\s*\([^{]*\{)', c)
if m:
    c = c[:m.end()] + spoof_code + c[m.end():]
    print(f'[OK] Deck emu ({device_name}) applied')
else:
    print('[WARN] Properties function not found for deck emu')

if 'DECK_EMU_PERF_INIT' not in c:
    inc = c.find('#include')
    if inc != -1:
        eol = c.find('\n', inc)
        c = c[:eol+1] + turbo_init + c[eol+1:]
    init_m = re.search(r'(tu_physical_device_init\s*\([^)]*\)\s*\{)', c)
    if not init_m:
        init_m = re.search(r'(tu_CreateDevice\s*\([^)]*\)\s*\{)', c)
    if init_m:
        ins = c.find('\n', c.find('{', init_m.start())) + 1
        c = c[:ins] + perf_call + c[ins:]
        print('[OK] Deck perf init injected into device creation')
with open(fp, 'w') as f: f.write(c)
