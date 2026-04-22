# Raspberry Pi Zero 2 W System Notes

Target-specific, implementation-coupled notes for `system_rpi02w`
(Raspberry Pi Zero 2 W: BCM2710A1 / Cortex-A53 / ARMv8).

## Hardware

| Property | Value |
|---|---|
| Board | Raspberry Pi Zero 2 W |
| SoC | Broadcom BCM2710A1 |
| CPU | Quad-core Cortex-A53 (ARMv8-A) |
| RAM | 512 MiB |
| Wi-Fi/BT | BCM43436, 802.11n + BT 4.2 |

## Current Target Shape

- Target name: `rpi02w`
- System directory: `system_rpi02w/`
- Toolchain tuple: `aarch64-unknown-linux-gnu`
- Toolchain configs:
  - `toolchain/configs/rpi02w_linux_x86_64_defconfig`
  - `toolchain/configs/rpi02w_linux_aarch64_defconfig`
- Kernel source pin: `raspberrypi/linux` tag `stable_20250916`
- Kernel DTB staged into firmware: `bcm2710-rpi-zero-2-w.dtb`

## Boot and Update Model

`system_rpi02w` follows the same model as `system_rpi0w`:

- No U-Boot bootloader in the boot chain.
- VideoCore firmware + `tryboot` A/B boot selection.
- Same GRiSP Alloy fwup task vocabulary and uboot-env schema
  (`complete`, `upgrade.{a,b}`, `validate.{a,b}`, `rollback.{a,b}`).

Key files:

- `defconfig`: Buildroot target configuration.
- `linux/linux-6.12.defconfig`: custom kernel config seed.
- `fwup.conf`: firmware packaging and A/B task logic.
- `config.txt`, `cmdline-*.txt`, `autoboot-*.txt`: staged boot artifacts.
- `rootfs_overlay/etc/erlinit.config`: runtime init and console selection.

## Status

This is an initial target scaffold derived from `system_rpi0w` and adapted
for the Zero 2 W architecture and DTB path.

- Build integration is wired through the four-stage pipeline.
- Hardware validation is still required (boot, Wi-Fi/BT, A/B lifecycle).
