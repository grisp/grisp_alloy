# Raspberry Pi Zero W System Notes

Target-specific, implementation-coupled notes for `system_rpi0w`
(Raspberry Pi Zero W v1.1 — BCM2835 / ARM1176JZF-S / ARMv6).


## Hardware

| Property | Value |
|---|---|
| Board    | Raspberry Pi Zero W (v1.1, 2017) |
| SoC      | Broadcom BCM2835 |
| CPU      | ARM1176JZF-S @ 1 GHz, ARMv6 + VFPv2 (hard-float) |
| RAM      | 512 MiB |
| Wi-Fi/BT | BCM43430 — 802.11n + BT 4.1 |

Not compatible with **Raspberry Pi Zero 2 W** (BCM2710A1 / Cortex-A53 /
ARMv8). That variant would need a separate `system_rpi02w` target.

## Version pins

| Component    | Value | Notes |
|---|---|---|
| Toolchain    | `0.1` | New ARMv6 toolchain (`armv6-unknown-linux-gnueabihf`) |
| Kernel       | `raspberrypi/linux` tag `stable_20250916` | Raspberry Pi downstream tree |
| RPi firmware | `1.20250915` | Matches the pinned kernel tree |

## Boot chain

No bootloader. VideoCore GPU firmware loads the kernel directly.

```text
VideoCore GPU ROM
  -> AUTOBOOT partition (mmcblk0p1, FAT32, MBR primary 0, 'boot' flag)
       - bootcode.bin                  (from rpi-firmware)
       - autoboot.txt                  (tryboot_a_b=1, boot_partition=2 or 3)
  -> switches to BOOT-A (p2) or BOOT-B (p3)
       - start.elf, fixup.dat          (from rpi-firmware)
       - config.txt                    (kernel=zImage, overlays, enable_uart)
       - cmdline.txt                   (root=/dev/mmcblk0p5|p6, console=serial0)
       - zImage, bcm2708-rpi-zero-w.dtb
       - overlays/*.dtbo
Linux 6.12 (RPi stable_20250916)
  -> erlinit (-c ttyAMA0) -> /srv/erlang -> project release
```

**Partition layout**:

| Linux dev       | MBR idx | Kind         | Purpose                          |
|-----------------|---------|--------------|----------------------------------|
| `mmcblk0p1`     | 0       | FAT32        | AUTOBOOT (`autoboot.txt`, `bootcode.bin`) |
| `mmcblk0p2`     | 1       | FAT32        | BOOT-A (per-slot kernel + DTB + overlays) |
| `mmcblk0p3`     | 2       | FAT32        | BOOT-B (same, slot B)            |
| `mmcblk0p4`     | 3       | Extended     | container                        |
| `mmcblk0p5`     | 4       | squashfs     | rootfs A                         |
| `mmcblk0p6`     | 5       | squashfs     | rootfs B                         |
| `mmcblk0p7`     | 6       | ext4         | app (mounted at `/root`)         |

Firmware metadata lives in a `uboot-environment` KV block at SD offset
`0x2000` (size `0x2000`). `fw_printenv` / `fw_setenv` read/write it, but
**no U-Boot bootloader runs** — the format is just a convenient KV
store that the `fwup` and `libubootenv` tools already understand. The
schema (`alloy_env_ver`, `valid_system`, `active_system`,
`upgrade_available`, `upgrade_fallback`, `rollback_available`,
`bootcount`, `system_platform`, `system_architecture`, per-slot
`systema_firmware_*` / `systemb_firmware_*`, `bootargs_extra`) mirrors
`system_kontron-albl-imx8mm/fwup.conf`, so `grisp_updater` and related
userland tooling treat this target the same as the kontron one.

Differences from existing targets:

- `system_grisp2` relies on a pre-flashed barebox in NAND. Here there is
  no bootloader at all — neither pre-flashed nor built.
- `system_kontron-albl-imx8mm` builds U-Boot + ATF + FIT, and U-Boot
  reads `valid_system` at every boot. We have no bootloader, so the
  `validate.{a,b}` / `rollback.{a,b}` fwup tasks additionally rewrite
  `autoboot.txt` on the AUTOBOOT partition (copying `autoboot-a.txt` or
  `autoboot-b.txt` onto it) to tell the GPU firmware which slot to pick
  on the next normal reboot.

A/B slot switching uses the RPi `tryboot` feature together with the
alloy task set. `fwup -t upgrade.{a,b}` stages the new slot and issues
`reboot_param("0 tryboot")` so the GPU boots the other slot once; once
healthy the application calls `fwup -t validate.{a,b}`, which sets
`valid_system=<slot>`, clears `upgrade_available`, enables
`rollback_available`, and rewrites `autoboot.txt` to make the slot
sticky.

## Console

- Serial: `ttyAMA0` @ 115 200 baud on GPIO 14 (TXD) / GPIO 15 (RXD) —
  requires a 3.3 V USB-UART adapter.
- Alternate: USB CDC composite (serial + ECM ethernet) via
  `dtoverlay=dwc2` on the Pi's data USB port.
