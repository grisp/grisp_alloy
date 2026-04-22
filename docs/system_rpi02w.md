# `system_rpi02w`: Architecture Notes

Design note for the Raspberry Pi Zero 2 W target.

## Overview

`system_rpi02w` is the Pi Zero 2 W sibling of `system_rpi0w`.
It keeps the same GRiSP Alloy update model (`fwup` tasks + uboot-env
schema + tryboot flow), but moves to a Cortex-A53/ARMv8 (aarch64)
toolchain and the Zero 2 W DTB.

## Key Deltas vs `system_rpi0w`

- Target name: `rpi02w`
- Toolchain tuple: `aarch64-unknown-linux-gnu`
- Crosstool configs:
  - `toolchain/configs/rpi02w_linux_x86_64_defconfig`
  - `toolchain/configs/rpi02w_linux_aarch64_defconfig`
- Buildroot arch selection in `system_rpi02w/defconfig`:
  - `BR2_aarch64=y`
  - `BR2_cortex_a53=y`
- Firmware DTB payload in `system_rpi02w/fwup.conf`:
  - `bcm2710-rpi-zero-2-w.dtb`
- Kernel file consumed by fwup from SDK images:
  - `${GRISP_SYSTEM}/images/Image` (packaged as `kernel8.img` in BOOT-A/B)

See also:
- [`porting-notes-rpi02w.md`](./porting-notes-rpi02w.md) for a
  checklist-style delta from `system_rpi0w`.

## Build Pipeline Usage

```sh
./build-toolchain.sh rpi02w
./build-sdk.sh rpi02w
./build-project.sh rpi02w <project>
./build-firmware.sh rpi02w <artefact-prefix-or-path>
```

## Status

- Integrated into repo structure and Vagrant provisioning.
- Boot to Erlang shell confirmed on hardware.
- Bluetooth HCI UART support requires rebuilt kernel/SDK after
  `linux-6.12.defconfig` updates.
