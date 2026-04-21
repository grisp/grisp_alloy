# Porting notes: gotchas from the `system_rpi0w` bring-up

A short, honest field notebook: traps we actually hit while adding
`system_rpi0w`, with links to the concrete files. Sample size is one
port, so treat these as "read before you start", not as a finished
porting guide. When we add the next target this file should grow into
a proper checklist; until then it's just the things that cost us time.

- [1. Unknown Buildroot package symbols fail silently](#1-unknown-buildroot-package-symbols-fail-silently)
- [2. Prefer a full custom kernel defconfig over base + fragment](#2-prefer-a-full-custom-kernel-defconfig-over-base--fragment)
- [3. `=m` kernel modules need an explicit autoload path; SDIO coldplug is racy](#3-m-kernel-modules-need-an-explicit-autoload-path-sdio-coldplug-is-racy)
- [4. USB gadget function drivers have no autoload trigger; keep them `=y`](#4-usb-gadget-function-drivers-have-no-autoload-trigger-keep-them-y)
- [5. Console-path alignment: three files must agree](#5-console-path-alignment-three-files-must-agree)
- [6. Everything `fwup.conf` references must be staged by `post-build.sh`](#6-everything-fwupconf-references-must-be-staged-by-post-buildsh)
- [7. Partition offsets live in one file](#7-partition-offsets-live-in-one-file)
- [8. The alloy task vocabulary is stable; the boot mechanism under it is not](#8-the-alloy-task-vocabulary-is-stable-the-boot-mechanism-under-it-is-not)
- [9. Rebuild flags: when to pass `-p linux`](#9-rebuild-flags-when-to-pass--p-linux)
- [10. BusyBox `command -v` / `which` can lie](#10-busybox-command--v--which-can-lie)
- [11. Raspberry-Pi ACT LED flash codes (rpi family only)](#11-raspberry-pi-act-led-flash-codes-rpi-family-only)

## 1. Unknown Buildroot package symbols fail silently

Setting `BR2_PACKAGE_DOES_NOT_EXIST=y` in a `defconfig` produces **no
build-time warning**. Buildroot quietly drops the line on next
`make olddefconfig`; the package is not built; the runtime symptom
is "the files I expected in `/lib/firmware/` / `/usr/bin/` / wherever
just aren't there".

We hit this with `BR2_PACKAGE_RPI_DISTRO_FIRMWARE_NONFREE=y`, a symbol
that doesn't exist in Buildroot 2025.05. Result: `/lib/firmware/brcm/`
empty, `brcmfmac` refused to probe, no `wlan0`.

**Mitigation**:

- Before adding a `BR2_PACKAGE_*` symbol, verify it exists: `rg -n
  '<symbolname>' /path/to/buildroot/package/` or `make menuconfig` then
  `/` search.
- After a successful SDK build, spot-check the staged `target/` tree:
  ```sh
  ls buildroot/output/target/lib/firmware/<vendor>/
  ls buildroot/output/target/usr/sbin/ | grep <tool>
  ```
- See `system_rpi0w/defconfig` (Wi-Fi / BT section) for the correct
  package names (`BR2_PACKAGE_BRCMFMAC_SDIO_FIRMWARE_RPI{,_WIFI,_BT}`).

## 2. Prefer a full custom kernel defconfig over base + fragment

First bring-up pattern we tried: take Buildroot's upstream
`bcmrpi_defconfig` and overlay a tiny `linux.fragment` with the
handful of symbols we wanted changed. It looked small and tidy.
It did not work, and the failure mode is instructive.

**Symptom**: after the first flash, `/lib/modules/<kver>/modules.dep`
was a 0-byte file. `modprobe brcmfmac` returned
`module brcmfmac not found in modules.dep`. No wlan0, no hci0.
`brcmfmac.ko.xz` was visibly present in `/lib/modules/.../kernel/`.

**Two independent root causes, both tied to Kconfig**:

1. `bcmrpi_defconfig` sets `CONFIG_MODULE_COMPRESS_XZ=y`, so every
   module is installed as `.ko.xz`. Buildroot's `host-kmod` on this
   target is linked **without** XZ/ZSTD/ZLIB decompressors
   (`${HOST_DIR}/sbin/depmod --version` reports `-XZ -ZSTD -ZLIB`);
   it can list the files but cannot extract ELF modinfo to build
   the dependency graph. `modules.alias` comes out populated,
   `modules.dep` stays empty.
2. The fragment *tried* to fix this with
   `CONFIG_MODULE_COMPRESS_NONE=y`. That override did not stick.
   `MODULE_COMPRESS_*` is a Kconfig `choice` group, and Buildroot's
   `merge_config.sh` + `make olddefconfig` keep the base defconfig's
   choice over any fragment override. The same mechanism silently
   demotes fragment-side `=y` promotions of `CFG80211`, `MAC80211`,
   `BRCMFMAC`, `BT`, `BT_HCIUART` when the base has them `=m` with
   unmet dependencies; the final `.config` keeps `=m`, and the
   fragment never warns.

**Fix**: drop the fragment approach for driver-heavy targets. Use
`BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y` +
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="${GRISP_TARGET_SYSTEM_DIR}/linux/<target>.defconfig"`
pointing at a full custom defconfig that we own end-to-end. This
is the same idiom `system_grisp2` and `system_kontron-albl-imx8mm`
already use, and it's what Nerves uses for `nerves_system_rpi0`.

Concretely on rpi0w we moved from
`linux/linux.fragment` (87 lines) to
`linux/linux-6.12.defconfig` (~370 lines, seeded from Nerves'
equivalent). With `MODULE_COMPRESS_*` simply unset, the kernel
default is `MODULE_COMPRESS_NONE`, modules install as plain `.ko`,
Buildroot's own `modules_install` + `depmod` pass writes a valid
`modules.dep`, and `post-build.sh` no longer needs the `xz -d`
workaround.

**Watch-outs when hand-crafting the defconfig**:

- `BT_HCIUART_SERDEV` requires `CONFIG_SERIAL_DEV_BUS=y`. Without
  it, `make olddefconfig` silently drops `BT_HCIUART_SERDEV`, which
  in turn drops `BT_HCIUART_BCM`, which drops `BT_BCM`, which means
  the miniuart-bt line-discipline driver is absent and `btattach`
  has nothing to bind.
- Always diff the generated `.config` against what you wrote. The
  canonical post-build verification is:
  ```sh
  grep -E "^CONFIG_(MODULE_COMPRESS|BRCMFMAC=|BT=|BT_HCIUART|BT_BCM|USB_G_SERIAL|SQUASHFS_XZ|CFG80211=|MAC80211=|MODVERSIONS)" \
    _build/system/build/build/linux-custom/.config | sort
  ```
  Anything present in the defconfig but missing here was dropped
  for an unmet dependency.

**Quick on-target sanity check**:

```sh
wc -l /lib/modules/*/modules.dep    # must be > 0 (we currently see ~120 lines)
cat /proc/modules                    # what actually loaded at boot
dmesg | grep -i <driver>             # probe log
```

## 3. `=m` kernel modules need an explicit autoload path; SDIO coldplug is racy

A module being built as `=m` and correctly listed in `modules.dep`
is a necessary but not sufficient condition for it actually loading
at boot. Something has to *fire* the load. Three mechanisms in
practice:

| Mechanism                               | Works for                             | Notes                                                                                                   |
| --------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Device-tree `compatible` binding        | `hci_uart` via `miniuart-bt` overlay  | Kernel's serdev layer resolves the `compatible` string and requests the driver module. Deterministic. |
| Bus `modalias` + usermode helper        | `brcmfmac` via SDIO coldplug          | Kernel calls `/proc/sys/kernel/modprobe` with the modalias. **Racy at boot**: fires before `/sbin/modprobe` has its file caches warmed. |
| Explicit `modprobe` from init script    | whatever the above didn't catch       | Deterministic. One-liner in `peripherals-init.sh`. Non-fatal (log-and-continue) so a missing module never bricks the board. |

The SDIO race cost us a full round of head-scratching. Typical
boot log:

```
[ 1.87 ] mmc1: new high speed SDIO card at address 0001
...
[prompt, no wlan0]
# modprobe brcmfmac
[215.87] brcmfmac: Firmware: BCM43430/1 ... 7.45.98 (TOB) ...
[wlan0 appears]
```

The kernel fires `request_module(brcmfmac)` at 1.87 s, but at that
moment userspace modprobe hasn't warmed `modules.dep`. The call
fails, the kernel doesn't retry. Easy fix: add an explicit
`modprobe brcmfmac` to `peripherals-init.sh`; see
[`system_rpi0w/rootfs_overlay/sbin/peripherals-init.sh`](../system_rpi0w/rootfs_overlay/sbin/peripherals-init.sh).

Rule of thumb: **anything that must come up before the BEAM starts,
modprobe it explicitly and log failures**. Don't rely on coldplug
autoload for drivers the board can't boot usefully without.

## 4. USB gadget function drivers have no autoload trigger; keep them `=y`

Unlike SDIO or DT-bound devices, USB gadget *function* drivers
(`g_serial`, `g_ether`, `g_ncm`, ...) have no bus-side modalias the
kernel can fire on. `dwc2` comes up in peripheral mode, sees no
gadget function registered, and exposes nothing. The host's
`/dev/tty.usbmodem*` never appears.

Two ways to make this deterministic:

- **Recommended**: build the whole gadget chain `=y` (static):
  ```
  CONFIG_USB_DWC2=y
  CONFIG_USB_GADGET=y
  CONFIG_USB_LIBCOMPOSITE=y
  CONFIG_USB_U_SERIAL=y
  CONFIG_USB_F_ACM=y
  CONFIG_USB_G_SERIAL=y
  ```
  The gadget registers itself the moment `dwc2` initialises. No
  userspace plumbing, no race.
- **Alternative**: keep them `=m` and add
  `/etc/modules-load.d/gadget.conf` listing `g_serial`. This works
  but depends on your init reading that directory (busybox `mdev`
  does not by default; erlinit doesn't run any module loader of
  its own), so you need glue in `peripherals-init.sh`.

On rpi0w we went with `=y`. The CDC-ACM console is part of the
board's bring-up contract (no console = no BEAM prompt = no
recovery), so we don't want any indirection between boot and the
USB device appearing on the host.

## 5. Console-path alignment: three files must agree

Getting the BEAM prompt on the tty you expect requires three files to
name the same device:

| File                          | Role                               | Example on rpi0w          |
| ----------------------------- | ---------------------------------- | ------------------------- |
| `cmdline-{a,b}.txt`           | Kernel `console=<tty>` entries     | `console=ttyAMA0,115200 console=ttyGS0` |
| `rootfs_overlay/etc/erlinit.config` | `-c <tty>`, BEAM prompt tty | `-c ttyGS0`               |
| `config.txt` (rpi only)       | DT overlay(s) that create the tty  | `dtoverlay=dwc2` for `ttyGS0`; `miniuart-bt` to keep `ttyAMA0` free |

**Erlinit only takes one `-c`**, so there is no automatic fallback:
if that tty doesn't enumerate you get no prompt. Putting *two*
`console=` entries in the kernel cmdline is still useful: kernel
messages (and oopses) fan out to both ttys, so a stuck BEAM doesn't
blind you on early-boot diagnostics. See the "Console" section of
`system_rpi0w/README.md` and the comment block at the top of
`system_rpi0w/rootfs_overlay/etc/erlinit.config`.

## 6. Everything `fwup.conf` references must be staged by `post-build.sh`

`fwup` resolves `host-path` relative to `$BINARIES_DIR` at firmware
assembly time, not out of your source tree. Any file
`system_<target>/fwup.conf` refers to via `${GRISP_SYSTEM}/...` must
be copied into `$BINARIES_DIR` by
`system_<target>/post-build.sh`.

On rpi0w this includes `config.txt`, `cmdline-{a,b}.txt`,
`autoboot-{a,b}.txt`, and the contents of `fwup_include/`. See
`system_rpi0w/post-build.sh`. A missing stage shows up as
`fwup: No such file or directory` during
`build-firmware.sh -i`.

## 7. Partition offsets live in one file

`system_<target>/fwup_include/fwup-common.conf` is the single source
of truth for partition offsets and sizes. Both `fwup.conf` and
`rootfs_overlay/etc/fw_env.config` should consume those macros (or
match them by hand: `fw_printenv` reads a raw offset and will happily
return gibberish if the two disagree). On rpi0w the uboot-env block is
8 KiB at byte offset 16 blocks (`0x2000` bytes, `0x200` blocksize),
mirrored across the environment config.

## 8. The alloy task vocabulary is stable; the boot mechanism under it is not

Across all targets the `fwup` task set is the same:

- `complete`: factory flash
- `upgrade.{a,b}`: write the inactive slot
- `validate.{a,b}`: mark the just-booted slot healthy
- `rollback.{a,b}`: revert to the other slot
- `status.*`: read-only diagnostics

The `uboot-env` KV schema is also common: `alloy_env_ver`,
`active_system`, `valid_system`, `upgrade_available`,
`rollback_available`, per-slot `system{a,b}_firmware_*` metadata.

**What changes between targets is how the bootloader picks a slot**:

- `system_grisp2` / `system_kontron-albl-imx8mm`: U-Boot reads the
  env block and branches on `valid_system` / `upgrade_available` /
  `bootcount`.
- `system_rpi0w`: there is no U-Boot. The VideoCore GPU firmware reads
  `autoboot.txt`, which `fwup`'s `validate.*` / `rollback.*` tasks
  rewrite via `fat_write(AUTOBOOT, "autoboot.txt")`.

**Implication for a new target**: if your board has U-Boot, copy the
`kontron` / `grisp2` schema verbatim. If it doesn't, look at `rpi0w`:
you'll need to translate each env mutation into an equivalent
filesystem- or raw-block mutation on the boot artefact the ROM
actually reads. See `docs/system_rpi0w.md` §5 for the tryboot
adaptation.

## 9. Rebuild flags: when to pass `-p linux`

`build-sdk.sh` caches the extracted and already-configured kernel
source tree under `_build/system/build/build/linux-custom/`. A plain
`build-sdk.sh -r <target>` re-runs Buildroot but does **not** re-run
the kernel's Kconfig against an updated defconfig: `make` sees an
existing `linux-custom/.config` and leaves it alone.

This matters when iterating on `system_<target>/linux/<target>.defconfig`:
the updated file is staged into the VM (via `-P`), but unless the
`linux-custom` build dir is wiped the kernel `.config` silently keeps
the stale copy. Classic symptom: defconfig edit doesn't appear in the
built `.config`.

Flag matrix we've settled on:

| Changed file(s)                                              | Command                                               |
| ------------------------------------------------------------ | ----------------------------------------------------- |
| `system_<target>/rootfs_overlay/**`, `post-build.sh`         | `build-sdk.sh -P -r <target>`                         |
| `system_<target>/defconfig` (Buildroot-level)                | `build-sdk.sh -P -r <target>`                         |
| `system_<target>/linux/<target>.defconfig` (kernel-level)    | `build-sdk.sh -P -r -p linux <target>`                |
| Kernel version bump, toolchain bump, anything structural     | `build-sdk.sh -P -c <target>` (full clean)            |

Follow either of the first three with
`build-project.sh <target> <project> && build-firmware.sh <target> <project>`
to get a fresh `.fw`. `build-sdk.sh` alone never rebuilds the
firmware; it only produces the SDK.

`-K` (keep vagrant running) pairs well with any of these when you
expect to follow up with flashing and on-device verification; the
script's default is to `vagrant halt` on exit.

## 10. BusyBox `command -v` / `which` can lie

Doing `command -v iw` or `which iw` over a serial Erlang shell can
return MISSING while `ls -la /usr/sbin/iw` shows the binary.
BusyBox's multi-call `sh` is sensitive to `PATH` and login-mode
state; the Erlang `os:cmd/1` environment may not inherit what you
expect. BusyBox's own `which` applet also behaves differently
depending on whether `BR2_PACKAGE_BUSYBOX_INSTALL_LINKS` is enabled.

When auditing what's actually on the rootfs during bring-up, prefer:

```erlang
os:cmd("ls -la /usr/sbin /usr/bin /sbin 2>&1 | grep -E 'iw|wpa|bluetooth'")
```

over `command -v` / `which`. This is a diagnostic-only trap; real
init scripts that use absolute paths (as `peripherals-init.sh` does)
are unaffected.

## 11. Raspberry-Pi ACT LED flash codes (rpi family only)

When the board won't boot at all and you have no serial adapter, the
green ACT LED is your only signal. The GPU firmware reports its own
errors:

| Flashes | Meaning                                                    |
| ------- | ---------------------------------------------------------- |
| 3       | `start*.elf` not found / unreadable on the boot partition  |
| 4       | `start*.elf` could not find or load the kernel (check `kernel=` in `config.txt`, check that `zImage` is actually on the BOOT FAT, check `cmdline.txt` points at a real root) |
| 7       | Kernel loaded but not a valid arm binary                   |
| 8       | SDRAM init failed (hardware)                               |

Reference: <https://www.raspberrypi.com/documentation/computers/configuration.html#led-warning-flash-codes>

This is rpi-specific, but worth recording because "4 flashes" cost us
a full bring-up session before we realised it was a cmdline
root-device mismatch, not a kernel problem.
