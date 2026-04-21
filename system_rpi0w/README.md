# Raspberry Pi Zero W System Notes

Target-specific, implementation-coupled notes for `system_rpi0w`
(Raspberry Pi Zero W v1.1: BCM2835 / ARM1176JZF-S / ARMv6).


## Hardware

| Property | Value |
|---|---|
| Board    | Raspberry Pi Zero W (v1.1, 2017) |
| SoC      | Broadcom BCM2835 |
| CPU      | ARM1176JZF-S @ 1 GHz, ARMv6 + VFPv2 (hard-float) |
| RAM      | 512 MiB |
| Wi-Fi/BT | BCM43430, 802.11n + BT 4.1 |

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
| `mmcblk0p7`     | 6       | ext4         | application data (not auto-mounted today; `/root` is a 1 MiB tmpfs in `erlinit.config`, and application code is expected to mount or format `p7` itself) |

Firmware metadata lives in a `uboot-environment` KV block at SD offset
`0x2000` (size `0x2000`). `fw_printenv` / `fw_setenv` read/write it, but
**no U-Boot bootloader runs**. The format is just a convenient KV
store that the `fwup` and `libubootenv` tools already understand. The
schema (`alloy_env_ver`, `valid_system`, `active_system`,
`upgrade_available`, `upgrade_fallback`, `rollback_available`,
`bootcount`, `system_platform`, `system_architecture`, per-slot
`systema_firmware_*` / `systemb_firmware_*`, `bootargs_extra`) mirrors
`system_kontron-albl-imx8mm/fwup.conf`, so `grisp_updater` and related
userland tooling treat this target the same as the kontron one.

Differences from existing targets:

- `system_grisp2` relies on a pre-flashed barebox in NAND. Here there is
  no bootloader at all, neither pre-flashed nor built.
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

- **Primary: `ttyGS0`**. USB-OTG CDC-ACM serial gadget exposed via
  `dtoverlay=dwc2` + `g_serial` on the Pi Zero W's middle micro-USB
  port (labelled "USB"). The same cable powers the board, so a single
  micro-USB is enough for headless bring-up. On the host:
  `picocom -b 115200 /dev/tty.usbmodem*` (macOS) or
  `picocom -b 115200 /dev/ttyACM0` (Linux). This is what
  `erlinit.config` selects via `-c ttyGS0`.
- **Secondary: `ttyAMA0`**. PL011 UART on GPIO14 (TXD) / GPIO15 (RXD),
  115 200 8N1, via a 3.3 V USB-UART adapter. `cmdline-*.txt` lists both
  devices on `console=`, so kernel boot messages also appear here even
  though the BEAM prompt does not (erlinit drives a single tty). Useful
  when the USB gadget hasn't come up yet (e.g. debugging a kernel oops).
  `dtoverlay=miniuart-bt` in `config.txt` routes Bluetooth to the
  mini-UART so `ttyAMA0` stays exclusively the Linux console.

No ethernet gadget (`g_ether` / composite CDC-ECM) is configured; USB
provides serial only.

## What's enabled and what's pending

See [`../docs/system_rpi0w.md` §8 Status](../docs/system_rpi0w.md#8-status)
for the full peripheral-by-peripheral breakdown (build + boot, on-board
peripherals, GPIO header, camera / display, networking). Short version:

- **Working, tested on hardware**: USB-OTG CDC-ACM console, PL011 UART,
  MicroSD / SDHCI, Wi-Fi (`wlan0` up), Bluetooth (`hci0` up), pstore /
  ramoops, ACT LED heartbeat.
- **Kernel ready, userspace gaps**: GPIO chardev (`libgpiod` not shipped),
  I2C (`i2c-tools` not shipped), SPI, 1-wire, PWM, I2S audio, watchdog,
  WireGuard, hardware RNG (no `rngd` wired up).
- **Opt-in**: CSI camera stack (sensor drivers compiled, userspace
  `libcamera` / `v4l-utils` not shipped by default), DSI touchscreen
  panel overlay (kernel ready, overlay not enabled in `config.txt`).
- **Not in scope**: USB Ethernet gadget (we deliberately chose CDC-ACM
  serial on the OTG port), USB host mode, HDMI console.

The user-visible A/B update lifecycle (`upgrade.*`, `validate.*`,
`rollback.*`) is wired into `fwup.conf` but has not yet been exercised
end-to-end on real hardware; no GRiSP-Alloy update-package emitter
(`BOOTSCHEME=RPI`) exists yet either.

## Peripherals brought up before the BEAM

[`rootfs_overlay/sbin/peripherals-init.sh`](./rootfs_overlay/sbin/peripherals-init.sh)
runs as an erlinit `--pre-run-exec`. Failures are logged but never
fatal: the BEAM must always come up, so a missing Wi-Fi / BT module
should degrade the system, not brick it.

| Step                           | Status by prompt time                                  |
| ------------------------------ | ------------------------------------------------------ |
| `modprobe brcmfmac`            | `wlan0` up, SDIO enumerated, firmware `7.45.98 (TOB)` loaded |
| `modprobe hci_uart` (defensive, may already be loaded by serdev) | `hci_uart` + `btbcm` present |
| Mount pstore on `/sys/fs/pstore` | previous boot's kernel log exposed as `dmesg-ramoops-*` |
| `btattach -B /dev/ttyAMA1 -P bcm -S 3000000 &` | `hci0` up, `BCM43430A1` patchram applied |

`wpa_supplicant` association and `bluetoothctl` pairing are **not**
started by `peripherals-init.sh`: they are the application's
responsibility (or a future GRiSP OTP runtime hook). What the init
script guarantees is that by the time the BEAM starts, the kernel
drivers are loaded, the controllers are initialised, and the
corresponding `/dev/` and `/sys/class/` entries exist.

## Credits and prior art

This target would not exist in its current form without
[`nerves_system_rpi0`](https://github.com/nerves-project/nerves_system_rpi0)
by Frank Hunleth and the Nerves Project contributors. Years of careful
bring-up work on the Pi Zero W (figuring out the bootloader-less
`tryboot` + `autoboot.txt` dance, the partition layout, the right
`fwup` idioms, the Broadcom firmware packaging, the `config.txt`
tunings, the `miniuart-bt` routing trick) saved us months of
independent trial and error.

Concretely, `system_rpi0w` borrows **patterns and conventions** from
`nerves_system_rpi0`:

- The overall **boot mechanism**: no bootloader; VideoCore GPU firmware
  reads `autoboot.txt`; tryboot one-shot selects the inactive slot.
- The **7-partition MBR layout** (AUTOBOOT + BOOT-A/B FAT + extended
  container with ROOTFS-A/B + APP).
- The `fat_touch("config.txt")` trick in `fwup.conf` to keep `fwup`
  from complaining about FAT side-effects mid-task (see inline
  comment in `fwup.conf`).
- The **`autoboot-a.txt` / `autoboot-b.txt` + live `autoboot.txt`**
  pair-of-files-plus-copy pattern.
- Specific `config.txt` values: `gpu_mem=192`, `camera_auto_detect=1`,
  the ACT-LED heartbeat trigger, the `miniuart-bt` overlay choice to
  keep PL011 free for the Linux console.
- The **`brcmfmac_sdio-firmware-rpi`** Buildroot package choice for
  BCM43430 firmware.
- **Static `/dev/mmcblk0pN` naming**, `/root` as tmpfs, APP partition
  auto-format on first boot.

The A/B firmware-update machinery that rides on top of that boot
mechanism, the `fwup` task vocabulary (`complete`, `upgrade.*`,
`validate.*`, `rollback.*`, `status.*`) and the `uboot-env` KV schema
it runs on, is the work of the **Peer Stritzinger GmbH team**. It is
shared verbatim across every grisp_alloy target: `system_grisp2`,
`system_kontron-albl-imx8mm`, and now `system_rpi0w`.

The rpi0w-specific contribution is the bridge between that model and
a chip with no bootloader: on kontron and grisp2, U-Boot reads
`valid_system` from the env at every boot; here `validate.*` and
`rollback.*` additionally `fat_write` the AUTOBOOT partition's
`autoboot.txt` so the VideoCore GPU firmware picks the right slot on
the next reboot. `upgrade.*` likewise pre-sets `active_system` to the
target slot before issuing the tryboot reboot, so that the
validation-window `status.*` diagnostic tasks match cleanly.

### Licensing

`nerves_system_rpi0` ships per-file SPDX metadata via
[REUSE](https://reuse.software/). The specific files whose patterns we
drew on most heavily (`fwup.conf`, `fwup_include/*`, `config.txt`,
`cmdline-*.txt`, `rootfs_overlay/etc/erlinit.config`,
`rootfs_overlay/etc/fw_env.config`) are dedicated to the public
domain under [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/)
in Nerves' own [`REUSE.toml`](https://github.com/nerves-project/nerves_system_rpi0/blob/main/REUSE.toml).
Choosing CC0 for those files was a deliberately generous act on the
Nerves project's part, and we're glad to acknowledge it.

Our `fwup.conf`, `post-build.sh`, `config.txt`, `cmdline-*.txt`,
`autoboot-*.txt`, and Buildroot `defconfig` are freshly written
against the upstream tools (`fwup`, Buildroot, the RPi kernel),
informed by Nerves' solutions to the non-obvious traps. Our kernel
config [`linux/linux-6.12.defconfig`](./linux/linux-6.12.defconfig)
is seeded from
[`nerves_system_rpi0/linux-6.12.defconfig`](https://github.com/nerves-project/nerves_system_rpi0/blob/main/linux-6.12.defconfig)
and adjusted for GRiSP-specific bits: CDC-ACM USB gadget on `ttyGS0`
(replacing Nerves' USB Ethernet), Bluetooth stack over UART for the
BCM43438 miniuart path, and squashfs XZ/ZLIB decompressors for our
A/B rootfs layout. We start from Nerves because they have already
done years of bring-up on this SoC; the GRiSP-specific edits are a
small delta on top, not a re-curation of the whole kernel.

For the broader picture of "what we learned porting this target",
see [`../docs/porting-notes.md`](../docs/porting-notes.md).

### Why not just use Nerves?

Reasonable question. `grisp_alloy` is inspired by Nerves and shares
the same primitives (Buildroot, upstream RPi kernel, `fwup`,
`erlinit`, `libubootenv`), but it is **not a fork**. Five reasons:

1. **Multi-target shared code.** `nerves_system_rpi0` is a
   self-contained single-target repo. `grisp_alloy` carries three
   sibling targets (`system_grisp2`, `system_kontron-albl-imx8mm`,
   `system_rpi0w`) that share `system_common/`, `scripts/`,
   `Vagrantfile`, the build scripts, and the A/B `fwup` task
   vocabulary (`complete` / `upgrade.*` / `validate.*` /
   `rollback.*` / `status.*`). Copying Nerves verbatim would break
   that sharing; we'd fork forever or drift.

2. **Pure-shell build, no Mix.** Nerves is Elixir-driven: `mix
   nerves.new_system`, `nerves_system_br` from hex.pm, shoehorn and
   nerves_runtime as hard deps. `grisp_alloy` is Bash + Buildroot
   + Vagrant, deliberately. Someone with just those three should be
   able to build a firmware image.

3. **Upstream proximity.** We use vanilla Buildroot 2025.05 and
   upstream RPi kernel tarball directly, no `BR2_GLOBAL_PATCH_DIR`
   and no custom Buildroot packages. Staying upstream-shaped means
   we can track Buildroot releases without fork maintenance.

4. **Industrial / sensor Erlang, not IoT hobbyist.** GRiSP users
   attach I2C / SPI / GPIO peripherals. We enable `libgpiod`,
   `i2c-tools`, `spidev` etc.; we don't ship camera, DRM/FB or
   audio stacks by default.

5. **Separated boot-mechanism vs update-mechanism layering.**
   Nerves' `fwup.conf` fuses the boot mechanism and the update
   pipeline. `grisp_alloy` separates them: on rpi0w we copy Nerves'
   boot mechanism (VideoCore -> `autoboot.txt` -> kernel) directly,
   but the update pipeline on top is the same `fwup` task
   vocabulary used on `system_grisp2` (Barebox-managed) and
   `system_kontron-albl-imx8mm` (U-Boot + AHAB). On rpi0w the glue
   between those two layers is `fat_write autoboot.txt` inside
   `validate.*` and `rollback.*`: there is no bootloader to read
   `valid_system` from an env block at every boot, so the live
   `autoboot.txt` plays that role.

None of these prevent us from taking maximum advantage of Nerves'
proven kernel configuration. Hence the verbatim inherit + thin
GRiSP-specific additions, documented above.

### What's ours, not Nerves'

Concretely, on top of the Nerves-derived patterns, the following
are written and maintained by the Peer Stritzinger GmbH team:

- **The A/B update task vocabulary** (`complete`, `upgrade.a` /
  `upgrade.b`, `validate.a` / `validate.b`, `rollback.a` /
  `rollback.b`, `status.a` / `status.b`) and the `uboot-env` KV
  schema it runs on, shared verbatim with `system_grisp2` and
  `system_kontron-albl-imx8mm`. See
  [`fwup.conf`](./fwup.conf) and
  [`fwup_include/fwup-common.conf`](./fwup_include/fwup-common.conf).
- **The `grisp_alloy` toolchain**. Nerves downloads a prebuilt
  `nerves_toolchain_armv6_nerves_linux_gnueabihf` from their GitHub
  releases. We build our own `armv6-unknown-linux-gnueabihf`
  toolchain via [crosstool-NG](https://crosstool-ng.github.io/) in
  [`build-toolchain.sh`](../build-toolchain.sh); see
  [`toolchain/configs/rpi0w_linux_*_defconfig`](../toolchain/configs/).
- **GRiSP OTP runtime integration**. Our Erlang/OTP is built from
  Buildroot with the runtime hooks the grisp_runtime / grisp NIF
  stack expects. Nerves layers their own `nerves_runtime` +
  `shoehorn` on top of vanilla OTP instead; different integration
  surface.
- **USB-OTG CDC-ACM console on `ttyGS0`** as the primary BEAM
  prompt, with hardware UART on `ttyAMA0` as the optional
  debug-only fallback. Nerves exposes their rpi0 over a USB
  ethernet gadget (`g_ether` / CDC-ECM, `CONFIG_USB_ETH=y`), which
  is a different UX choice: serial-over-USB lets you drive the
  BEAM with just `picocom`, no host network config.

Everything else (the kernel `.defconfig` in `linux/`, the specific
`fwup.conf` idioms for tryboot + autoboot.txt, the Broadcom Wi-Fi
firmware package choice, the `miniuart-bt` overlay to keep PL011
free) is from Nerves and we pull their patterns forward.

### Also standing on the shoulders of

- [**`fwup`**](https://github.com/fwup-home/fwup): Frank Hunleth's
  firmware update tool; our entire A/B lifecycle is expressed in its
  config language.
- [**`erlinit`**](https://github.com/nerves-project/erlinit): the
  minimal Erlang init system used across all grisp_alloy targets.
- [**Buildroot**](https://buildroot.org/): the root filesystem and
  toolchain build system underneath everything.
- [**`libubootenv`**](https://github.com/sbabic/libubootenv):
  provides `fw_printenv` / `fw_setenv` for the raw KV block, with
  no U-Boot required to run.
