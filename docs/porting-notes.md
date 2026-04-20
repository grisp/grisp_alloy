# Porting notes: gotchas from the `system_rpi0w` bring-up

A short, honest field notebook: traps we actually hit while adding
`system_rpi0w`, with links to the concrete files. Sample size is one
port, so treat these as "read before you start", not as a finished
porting guide. When we add the next target this file should grow into
a proper checklist; until then it's just the things that cost us time.

- [1. Unknown Buildroot package symbols fail silently](#1-unknown-buildroot-package-symbols-fail-silently)
- [2. `/lib/modules/` is empty on the rootfs, so drivers must be `=y`, not `=m`](#2-libmodules-is-empty-on-the-rootfs-so-drivers-must-be-y-not-m)
- [3. Console-path alignment: three files must agree](#3-console-path-alignment-three-files-must-agree)
- [4. Everything `fwup.conf` references must be staged by `post-build.sh`](#4-everything-fwupconf-references-must-be-staged-by-post-buildsh)
- [5. Partition offsets live in one file](#5-partition-offsets-live-in-one-file)
- [6. The alloy task vocabulary is stable; the boot mechanism under it is not](#6-the-alloy-task-vocabulary-is-stable-the-boot-mechanism-under-it-is-not)
- [7. BusyBox `command -v` can lie](#7-busybox-command--v-can-lie)
- [8. Raspberry-Pi ACT LED flash codes (rpi family only)](#8-raspberry-pi-act-led-flash-codes-rpi-family-only)

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

## 2. `/lib/modules/` is empty on the rootfs, so drivers must be `=y`, not `=m`

`system_common/defconfig` sets `BR2_LINUX_KERNEL_INSTALL_TARGET=n`, so
Buildroot builds the kernel but does **not** copy
`/lib/modules/<ver>/` into the target rootfs. `modprobe` therefore
has nothing to load. Any driver marked `=m` in your kernel config is
dead weight.

Concrete implication for a new target: **every driver needed at boot
or at peripheral bring-up must be `=y` in
`system_<target>/linux/linux.fragment`.**

We hit this with `brcmfmac` (Wi-Fi) and `BT_HCIUART_BCM`: upstream
`bcmrpi_defconfig` builds them as modules, and they silently didn't
load. The fix was to set them `=y` in the fragment (and their
dependencies: `CFG80211`, `MAC80211`, `BT`, ...).

**Quick check on the running target**:

```sh
cat /proc/modules       # empty on a properly-configured alloy rootfs
dmesg | grep -i <driver>  # "driver not found" means builtin is missing
```

See `system_rpi0w/linux/linux.fragment` for a worked example.

## 3. Console-path alignment: three files must agree

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

## 4. Everything `fwup.conf` references must be staged by `post-build.sh`

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

## 5. Partition offsets live in one file

`system_<target>/fwup_include/fwup-common.conf` is the single source
of truth for partition offsets and sizes. Both `fwup.conf` and
`rootfs_overlay/etc/fw_env.config` should consume those macros (or
match them by hand: `fw_printenv` reads a raw offset and will happily
return gibberish if the two disagree). On rpi0w the uboot-env block is
8 KiB at byte offset 16 blocks (`0x2000` bytes, `0x200` blocksize),
mirrored across the environment config.

## 6. The alloy task vocabulary is stable; the boot mechanism under it is not

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

## 7. BusyBox `command -v` can lie

Doing `command -v iw` over a serial Erlang shell can return MISSING
while `ls -la /usr/sbin/iw` shows the binary. BusyBox's multi-call
`sh` is sensitive to `PATH` and login-mode state; the Erlang
`os:cmd/1` environment may not inherit what you expect.

When auditing what's actually on the rootfs during bring-up, prefer:

```erlang
os:cmd("ls -la /usr/sbin /usr/bin /sbin 2>&1 | grep -E 'iw|wpa|bluetooth'")
```

over `command -v`. This is a diagnostic-only trap; real init scripts
that use absolute paths are unaffected.

## 8. Raspberry-Pi ACT LED flash codes (rpi family only)

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
