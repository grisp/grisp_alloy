# `rpi02w` Porting Notes (vs `rpi0w`)

This note captures what was different when bringing up `system_rpi02w`
from the existing `system_rpi0w` target.

## CPU / ABI

- SoC class changes from ARMv6 to ARMv8-A (`cortex-a53`).
- Userspace/toolchain moves from 32-bit ARM to `aarch64-unknown-linux-gnu`.
- New toolchain defconfigs:
  - `toolchain/configs/rpi02w_linux_x86_64_defconfig`
  - `toolchain/configs/rpi02w_linux_aarch64_defconfig`

## Kernel / Boot Artifacts

- Kernel image consumed by firmware is `kernel8.img` (sourced from Buildroot `Image`).
- DTB switches to `bcm2710-rpi-zero-2-w.dtb`.
- `config.txt` requires 64-bit boot settings:
  - `arm_64bit=1`
  - `kernel=kernel8.img`
  - explicit `start_file` / `fixup_file` selection
- `cmdline-a.txt` / `cmdline-b.txt` map to rootfs A/B:
  - `root=/dev/mmcblk0p5` and `root=/dev/mmcblk0p6`

## Firmware Layout / fwup

- `system_rpi02w/fwup_include/fwup-common.conf` intentionally mirrors
  `system_rpi0w` partition geometry to preserve the same A/B update style:
  - AUTOBOOT offset/count: `2048 / 32768`
  - BOOT-A offset/count: `34816 / 65536`
  - BOOT-B offset/count: `100352 / 65536`
  - ROOTFS-A offset/count: `167936 / 286720`
  - ROOTFS-B offset/count: `456704 / 286720`
  - APP offset/count: `745472 / 1048576 (expand)`
- `fwup.conf` keeps GRiSP A/B state semantics (`upgrade.*`, `validate.*`,
  `rollback.*`, `status.*`) while using Pi `tryboot` behavior via
  `autoboot.txt`.

## Console / Device Bring-up

- USB gadget serial remains the primary Erlang console (`ttyGS0`).
- UART console (`ttyAMA0`) remains enabled for early boot diagnostics.
- Bluetooth on mini-UART requires explicit kernel config enablement:
  - `CONFIG_BT_HCIUART`, `CONFIG_BT_HCIUART_BCM`,
    `CONFIG_BT_HCIUART_SERDEV`, `CONFIG_BT_BCM`
  - `CONFIG_SERIAL_DEV_BUS` and `CONFIG_SERIAL_DEV_CTRL_TTYPORT`

## Build / Integration Touchpoints

- Add `system_rpi02w` folder and `VERSION`.
- Add `system_rpi02w` provisioning entry in `Vagrantfile`.
- Add `rpi02w` to supported target list in top-level `README.md`.
- Add `system_rpi02w` docs entry in `docs/README.md`.

## Observed Bring-up Pitfalls

- Stale SD boot files can hide source fixes; verify BOOT-A `config.txt` and
  `cmdline.txt` match the current repo before concluding boot regressions.
- ACT LED heartbeat in `config.txt` can look like a fault blink pattern;
  use UART output to classify real early-boot failures.
