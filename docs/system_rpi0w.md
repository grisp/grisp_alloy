# `system_rpi0w`: Architecture and Design Reference

Design-level documentation for the Raspberry Pi Zero W target. Captures
the key decisions and runtime behaviour: partition layout, boot chain,
`uboot-env` schema, and the A/B update / validate / rollback lifecycle.
For the narrower implementation plan and decision log see
[`../system_rpi0w-plan.md`](../system_rpi0w-plan.md).

- [1. Overview](#1-overview)
- [2. SD card layout](#2-sd-card-layout)
- [3. Boot chain](#3-boot-chain)
- [4. `uboot-env` runtime schema](#4-uboot-env-runtime-schema)
- [5. A/B update lifecycle](#5-ab-update-lifecycle)
  - [5.1 State machine](#51-state-machine)
  - [5.2 Factory flash (`fwup -t complete`)](#52-factory-flash-fwup--t-complete)
  - [5.3 Upgrade + tryboot + validate](#53-upgrade--tryboot--validate)
  - [5.4 Rollback](#54-rollback)
- [6. Build pipeline](#6-build-pipeline)
- [7. File tree](#7-file-tree)
- [8. Status](#8-status)
- [9. References](#9-references)

## 1. Overview

`system_rpi0w` is a **hybrid** target: it uses the RPi Zero W's
bootloader-less boot chain (VideoCore GPU firmware + `tryboot_a_b`),
while adopting `grisp_alloy`'s runtime conventions (same `GRISP_FW_*`
defines, same `uboot-env` KV schema, same `fwup` task vocabulary)
verbatim from `system_kontron-albl-imx8mm/fwup.conf`. The only
rpi0w-specific deviation from the alloy task set is a `fat_write` of
`autoboot.txt` inside `validate.*` / `rollback.*`, the
bootloader-less equivalent of what kontron's U-Boot does at boot
time.

```mermaid
flowchart LR
    subgraph Host["Build host (macOS / Linux)"]
        T[build-toolchain.sh]
        S[build-sdk.sh]
        P[build-project.sh]
        F[build-firmware.sh]
        T --> S --> P --> F
    end
    subgraph Artefacts
        FW[".fw archive"]
        IMG[".img (dd to SD)"]
        TAR[".tar update package (optional)"]
    end
    F --> FW
    F --> IMG
    F -. optional .-> TAR
    subgraph Device["Raspberry Pi Zero W"]
        SD[(SD card)]
        VC["VideoCore GPU firmware"]
        K["Linux 6.12"]
        E["erlinit + BEAM"]
        SD --> VC --> K --> E
    end
    IMG -->|dd| SD
    FW -->|fwup -t complete / upgrade.*| SD
```

## 2. SD card layout

7-partition MBR. AUTOBOOT is primary 0 with `boot=true` so the BCM2835
ROM looks there first; BOOT-A and BOOT-B are FAT siblings; an extended
container holds three logical partitions for rootfs A/B and APP.

```
block offset         size       role                         Linux path
──────────────────────────────────────────────────────────────────────────
0                    1 block    MBR
16                   8 KiB      uboot-env KV store           (raw, no FS)
2048         (1 MiB) 16 MiB     AUTOBOOT FAT (boot=true)     /dev/mmcblk0p1
34816       (17 MiB) 32 MiB     BOOT-A FAT                   /dev/mmcblk0p2
100352      (49 MiB) 32 MiB     BOOT-B FAT                   /dev/mmcblk0p3
165888      (81 MiB) extended   extended container           /dev/mmcblk0p4
  └─ 167936 (82 MiB) 140 MiB    ROOTFS-A squashfs            /dev/mmcblk0p5
  └─ 456704(223 MiB) 140 MiB    ROOTFS-B squashfs            /dev/mmcblk0p6
  └─ 745472(364 MiB) 512 MiB    APP ext4 (expand = true)     /dev/mmcblk0p7
```

Offsets and sizes are sourced from
[`system_rpi0w/fwup_include/fwup-common.conf`](../system_rpi0w/fwup_include/fwup-common.conf)
as a single source of truth; `fwup.conf` and `etc/fw_env.config`
reference the same macros.

**Contents per partition at factory-flash time (`fwup -t complete`):**

| Partition | Contents                                                                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AUTOBOOT  | `bootcode.bin`, `autoboot.txt` (= `autoboot-a.txt`), `autoboot-a.txt`, `autoboot-b.txt`                                                                             |
| BOOT-A    | `start.elf`, `fixup.dat`, `config.txt`, `cmdline.txt` (= `cmdline-a.txt`), `zImage`, `bcm2708-rpi-zero{,-w}.dtb`, `overlays/dwc2.dtbo`, `overlays/miniuart-bt.dtbo`, `overlays/ramoops.dtbo` |
| BOOT-B    | Same files as BOOT-A, except `cmdline.txt` = `cmdline-b.txt`                                                                                                                                  |
| ROOTFS-A  | `rootfs.squashfs`                                                                                                                                                   |
| ROOTFS-B  | zero-filled (invalidated by `raw_memset`)                                                                                                                           |
| APP       | zero-filled (first boot auto-formats ext4)                                                                                                                          |

## 3. Boot chain

```mermaid
flowchart TD
    ROM["VideoCore ROM, BCM2835"]
    BC["Load bootcode.bin from AUTOBOOT"]
    AT["Read autoboot.txt"]
    DEC{"tryboot_a_b selects slot"}
    BA["Switch to BOOT-A (mmcblk0p2)"]
    BB["Switch to BOOT-B (mmcblk0p3)"]
    CT["Read config.txt + cmdline.txt"]
    FW["Load start.elf + fixup.dat"]
    KN["Load zImage + DTB + overlays"]
    LIN["Linux: init=erlinit, kernel console=ttyAMA0 + ttyGS0"]
    EI["erlinit: mount /boot vfat ro, tmpfs /root, tmpfs /var/log"]
    PI["pre-run-exec: rngd + peripherals-init.sh (pstore, btattach)"]
    BEAM["BEAM on /srv/erlang, prompt on ttyGS0 (USB-OTG CDC-ACM)"]

    ROM --> BC --> AT --> DEC
    DEC -->|"sticky = A (default), or tryboot one-shot = A"| BA
    DEC -->|"sticky = B, or tryboot one-shot = B"| BB
    BA --> CT
    BB --> CT
    CT --> FW --> KN --> LIN --> EI --> PI --> BEAM
```

**Slot selection is entirely driven by `autoboot.txt`**, the live copy
on the AUTOBOOT partition. Whichever slot was validated last is the
sticky default target; the other slot is the tryboot one-shot target.
That file is rewritten by `fwup -t validate.{a,b}` and
`fwup -t rollback.{a,b}` (see §5).

## 4. `uboot-env` runtime schema

An 8 KiB raw KV store at block 16. **No U-Boot actually reads this at
boot**: it's userland-only state, queried with `fw_printenv` and
mutated by `fwup` tasks. Adopted verbatim from
`system_kontron-albl-imx8mm/fwup.conf:230-272` so `grisp_updater` and
friends treat rpi0w the same as kontron from userland.

| Variable                                        | Type                            | Set by                                                   | Meaning                                                                                                                                                    |
| ----------------------------------------------- | ------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `alloy_env_ver`                                 | `"1"`                           | `complete`                                               | Schema version; all tasks guard on this.                                                                                                                   |
| `valid_system`                                  | `"a"` / `"b"`                   | `complete`, `validate.*`, `rollback.*`                   | The slot known to boot successfully (sticky).                                                                                                              |
| `active_system`                                 | `"a"` / `"b"`                   | `complete`, `upgrade.*` (predictive on-finish)           | The slot the device is running. rpi0w-specific: upgrade._ pre-sets this before tryboot-reboot so `status._.upgraded` tasks match in the validation window. |
| `upgrade_available`                             | `"0"` / `"1"`                   | `upgrade.*`, `validate.*`, `rollback.*`                  | 1 between `upgrade.*` and `validate.*`.                                                                                                                    |
| `upgrade_fallback`                              | `"0"` / `"1"`                   | placeholder (kontron symmetry; rpi0w never sets 1 today) | Reserved for future "revert after N failed boots" logic.                                                                                                   |
| `rollback_available`                            | `"0"` / `"1"`                   | `validate.*` (sets 1), `rollback.*` (sets 0)             | 1 after a successful validation; rollback is one-shot.                                                                                                     |
| `bootcount`                                     | int string                      | `upgrade.*`, `validate.*`, `rollback.*` (all reset to 0) | Placeholder for cross-target schema compat; no bootloader increments it on rpi0w.                                                                          |
| `system_platform`                               | `"rpi0w"`                       | `complete`                                               | Guarded by every task; mismatched `.fw` hits `*.wrongplatform`.                                                                                            |
| `system_architecture`                           | `"arm-unknown-linux-gnueabihf"` | `complete`                                               | Same.                                                                                                                                                      |
| `systema_firmware_{uuid,version,vcs_id,author}` | strings                         | `complete`, `upgrade.a`, `rollback.b`                    | Slot A metadata. UUID is filled from `${FWUP_META_UUID}`.                                                                                                  |
| `systemb_firmware_*`                            | strings                         | `complete` (empty), `upgrade.b`, `rollback.a`            | Slot B metadata.                                                                                                                                           |
| `bootargs_extra`                                | string                          | `complete` (empty)                                       | Hook for RT isolcpus / ramoops region; currently unused (cmdline-a/b.txt is the authoritative kernel cmdline).                                             |

## 5. A/B update lifecycle

### 5.1 State machine

States are tuples of `(running_slot, active_system, valid_system,
upgrade_available, rollback_available)`. Transition labels are the
`fwup` task that causes them (and a reboot, where applicable).

```mermaid
stateDiagram-v2
    [*] --> A_validated: fwup -t complete

    A_validated --> A_upgrading_B: fwup -t upgrade.b
    A_upgrading_B --> B_pending_val: reboot (tryboot to B)
    B_pending_val --> B_validated_rb: fwup -t validate.b
    B_pending_val --> A_validated: power cycle (tryboot one-shot expired)

    B_validated_rb --> B_upgrading_A: fwup -t upgrade.a
    B_upgrading_A --> A_pending_val: reboot (tryboot to A)
    A_pending_val --> A_validated_rb: fwup -t validate.a
    A_pending_val --> B_validated_rb: power cycle (tryboot one-shot expired)

    A_validated_rb --> B_validated: fwup -t rollback.b + reboot
    B_validated_rb --> A_validated: fwup -t rollback.a + reboot

    A_validated     : running=A  active=a  valid=a  upgrade=0  rollback=0
    A_validated_rb  : running=A  active=a  valid=a  upgrade=0  rollback=1
    B_validated     : running=B  active=b  valid=b  upgrade=0  rollback=0
    B_validated_rb  : running=B  active=b  valid=b  upgrade=0  rollback=1
    A_upgrading_B   : running=A  active=a  valid=a  upgrade=1  rollback=0
    B_upgrading_A   : running=B  active=b  valid=b  upgrade=1  rollback=0
    B_pending_val   : running=B  active=b  valid=a  upgrade=1  rollback=0
    A_pending_val   : running=A  active=a  valid=b  upgrade=1  rollback=0
```

**Mapping to `status.*` tasks** (read-only diagnostics; `fwup -t
status.<name>` errors out if none match):

| State                                               | Matching `status.*` task               |
| --------------------------------------------------- | -------------------------------------- |
| `A_validated`                                       | `status.a.validated_no_rollback`       |
| `A_validated_rb`                                    | `status.a.validated_with_rollback`     |
| `B_validated`                                       | `status.b.validated_no_rollback`       |
| `B_validated_rb`                                    | `status.b.validated_with_rollback`     |
| `A_upgrading_B`                                     | `status.a.upgrading`                   |
| `B_upgrading_A`                                     | `status.b.upgrading`                   |
| `A_pending_val`                                     | `status.a.upgraded`                    |
| `B_pending_val`                                     | `status.b.upgraded`                    |
| _(transient, post-rollback, pre-reboot; see §5.4)_ | `status.{a,b}.rollback_pending_reboot` |

### 5.2 Factory flash (`fwup -t complete`)

Run once per device, typically against `/dev/mmcblk0` with `fwup -a
-i <fw> -t complete -d <device>` or equivalent via Etcher / `dd`
of the matching `.img`.

```mermaid
sequenceDiagram
    autonumber
    participant host as Host fwup
    participant SD as SD card
    participant ENV as uboot-env

    host->>SD: mbr_write mbr
    host->>SD: fat_mkfs AUTOBOOT / BOOT-A / BOOT-B
    host->>SD: fat_mkdir overlays/ on BOOT-A + BOOT-B
    host->>SD: trim ROOTFS-A/B + APP

    host->>ENV: uboot_clearenv
    host->>ENV: alloy_env_ver=1, valid=a, active=a, upgrade=0, rollback=0
    host->>ENV: system_platform=rpi0w, system_architecture=...
    host->>ENV: systema_firmware_uuid=$FWUP_META_UUID + version + vcs_id + author
    host->>ENV: systemb_firmware_* = ""

    host->>SD: bootcode.bin -> AUTOBOOT
    host->>SD: autoboot-a.txt -> AUTOBOOT -- as itself and as autoboot.txt
    host->>SD: autoboot-b.txt -> AUTOBOOT
    host->>SD: start.elf / fixup.dat / config.txt / zImage / DTBs / overlays/* -> BOOT-A + BOOT-B
    host->>SD: cmdline-a.txt -> BOOT-A as cmdline.txt
    host->>SD: cmdline-b.txt -> BOOT-B as cmdline.txt

    host->>SD: rootfs.img -> ROOTFS-A via raw_write
    host->>SD: raw_memset ROOTFS-B -- invalidate
    host->>SD: raw_memset APP -- force first-boot format
```

**Why both BOOT-A _and_ BOOT-B are populated at factory time**: it means
the very first `fwup -t upgrade.b` is a pure rewrite of an already-
formatted FAT, not a format-then-populate. Tryboot-to-B after factory
flash just works.

### 5.3 Upgrade + tryboot + validate

The happy path A → B and back.

```mermaid
sequenceDiagram
    autonumber
    participant user as Operator or grisp_updater
    participant device as Pi Zero W userland
    participant fwup as fwup on device
    participant gpu as VideoCore firmware
    participant env as uboot-env

    Note over device: Starting state A_validated<br/>running=A, active=a, valid=a, upgrade=0, rollback=0
    user->>device: ssh + fwup -t upgrade.b new.fw
    device->>fwup: run upgrade.b
    fwup->>env: upgrade_available=0, rollback_available=0
    fwup->>env: systemb_firmware_* = ""
    fwup->>env: trim ROOTFS-B
    fwup->>fwup: fat_write all BOOT-B assets<br/>incl. cmdline-b.txt as cmdline.txt
    fwup->>fwup: raw_write rootfs.img -> ROOTFS-B
    fwup->>env: systemb_firmware_{uuid,version,vcs_id,author}<br/>active_system=b, upgrade_available=1, bootcount=0
    fwup->>gpu: reboot_param 0 tryboot
    Note over device: State A_upgrading_B
    gpu->>gpu: reset, read autoboot.txt, tryboot one-shot selects BOOT-B
    gpu->>device: boot BOOT-B -> kernel -> erlinit
    Note over device: State B_pending_val<br/>running=B, active=b, valid=a, upgrade=1
    device->>fwup: fwup -t validate.b<br/>from erlinit hook or app
    fwup->>env: valid_system=b, upgrade_available=0, bootcount=0, rollback_available=1
    fwup->>fwup: fat_write AUTOBOOT autoboot.txt = autoboot-b.txt -- now sticky
    Note over device: State B_validated_rb<br/>running=B, active=b, valid=b, upgrade=0, rollback=1
```

**Failure branch**: if the kernel or userland on the new slot crashes
before `validate.b` runs and the board power-cycles:

- `autoboot.txt` still contains `autoboot-a.txt`'s bytes (validate.b
  never wrote it).
- The tryboot one-shot has already been consumed.
- The sticky default (slot A) wins → back on A.
- `env` still says `active_system=b, valid_system=a, upgrade_available=1`,
  which no `status.*` task matches cleanly. `fwup -t rollback.a` or a
  subsequent `fwup -t upgrade.b` resets it.

This is the rpi0w analogue of kontron's "bootcount expired, revert to
`valid_system`": the mechanism differs but the observable outcome is
the same.

### 5.4 Rollback

Explicit operator action. Unlike upgrade, rollback does **not** use
tryboot. It rewrites `autoboot.txt` to point at the other slot as
the sticky default, so the next normal reboot goes there.

```mermaid
sequenceDiagram
    autonumber
    participant user as Operator
    participant device as Pi Zero W
    participant fwup as fwup
    participant env as uboot-env

    Note over device: Starting state B_validated_rb<br/>running=B, active=b, valid=b, upgrade=0, rollback=1
    user->>device: ssh + fwup -t rollback.a
    device->>fwup: run rollback.a
    fwup->>env: valid_system=a, rollback_available=0, bootcount=0
    fwup->>env: systemb_firmware_* = ""
    fwup->>fwup: fat_write AUTOBOOT autoboot.txt = autoboot-a.txt
    Note over device: Transient status.b.rollback_pending_reboot<br/>running=B, active=b, valid=a, upgrade=0, rollback=0
    user->>device: reboot -- explicit, fwup does NOT reboot itself
    Note over device: GPU reads autoboot.txt, sticky default selects BOOT-A
    Note over device: State A_validated<br/>running=A, active=a -- stale until next validate or upgrade<br/>valid=a
```

**Known quirk**: post-rollback-reboot, `active_system` in `env` still
reports the pre-rollback slot until the next `upgrade.*` or
`validate.*` runs. `fw_printenv active_system` will lie briefly.
Callers that care should reconcile against `/proc/cmdline` or
`findmnt /`. Setting `active_system` inside `rollback.*` would fix
this, but would also lie during the pre-reboot transient window;
neither choice is correct in all moments without a proper boot hook.
Revisit when we wire up a systemd / erlinit "sync active_system on
boot" unit.

## 6. Build pipeline

Four shell scripts in sequence, each consuming the output of the
previous and emitting exactly one artefact kind.

```mermaid
flowchart LR
    subgraph Toolchain
        ctng[crosstool-NG config<br/>toolchain/configs/rpi0w_linux_*_defconfig]
        T[build-toolchain.sh rpi0w]
        TCBIN["artefacts/<br/>grisp_toolchain_armv6_unknown_linux_gnueabihf-0.1.linux-&lt;host&gt;.tar.xz"]
        ctng --> T --> TCBIN
    end
    subgraph SDK
        S[build-sdk.sh rpi0w]
        BR[Buildroot 2025.05]
        DCF[system_rpi0w/defconfig<br/>+ system_common/defconfig]
        KFR[linux/linux-6.12.defconfig<br/>full custom kernel config]
        SDKBIN["/opt/grisp_alloy_sdk/&lt;host&gt;/rpi0w/&lt;ver&gt;/images/<br/>zImage + DTBs + rpi-firmware/* + rootfs.squashfs"]
        TCBIN --> S
        S --> BR
        DCF --> BR
        KFR --> BR
        BR --> SDKBIN
    end
    subgraph Project
        P[build-project.sh rpi0w samples/hello_grisp]
        TGZ["artefacts/*.tgz<br/>with PROJECT_TARGET_NAME=rpi0w"]
        SDKBIN --> P --> TGZ
    end
    subgraph Firmware
        F[build-firmware.sh -i rpi0w hello_grisp]
        FWUP[system_rpi0w/fwup.conf<br/>+ fwup_include/<br/>+ config.txt + cmdline-*.txt + autoboot-*.txt]
        POST[post-build.sh stages files<br/>to $BINARIES_DIR]
        ART["artefacts/<br/>*-rpi0w-*.fw<br/>*-rpi0w-*.img"]
        TGZ --> F
        FWUP --> F
        SDKBIN --> F
        POST -.-> F
        F --> ART
    end
```

Script responsibilities:

| Script                 | Input                                                                         | Output                                               | rpi0w-specific notes                                                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `build-toolchain.sh`   | `toolchain/configs/rpi0w_linux_{x86_64,aarch64}_defconfig`                    | `grisp_toolchain_armv6_*` tar.xz in `artefacts/`     | On non-Linux hosts, self-hoists into Vagrant; no darwin defconfig.                                                                                         |
| `build-sdk.sh`         | `system_rpi0w/defconfig` + `system_common/defconfig` + `linux/linux-6.12.defconfig` | Kernel + DTBs + `rpi-firmware/*` + `rootfs.squashfs` | Sources `crucible.sh` after SDK install for `BOOTSCHEME`, `SQUASHFS_PRIORITIES`, etc.                                                                |
| `build-project.sh`     | Sample or user project                                                        | `.tgz` with release bundle                           | `PROJECT_TARGET_NAME=rpi0w`.                                                                                                                               |
| `build-firmware.sh -i` | `.tgz` + `fwup.conf` + staged boot files                                      | `.fw` + `.img`                                       | `post-build.sh` stages `fwup_include/` + `config.txt` + `cmdline-{a,b}.txt` + `autoboot-{a,b}.txt` into `$BINARIES_DIR` so `fwup.conf` host-paths resolve. |
| `build-firmware.sh -u` | Same                                                                          | `.tar` update package                                | Needs `BOOTSCHEME=RPI` plugin; not wired up yet.                                                                                                           |

## 7. File tree

```
system_rpi0w/
├── VERSION                          "0.1.0"
├── Config.in                        (empty target-specific Buildroot opts)
├── external.desc                    informational "name: RPI0W"
├── external.mk                      placeholder for custom packages
├── crucible.sh                      BOOTSCHEME=NONE, FWUP_IMAGE_TARGETS=(complete), OS_RELEASE_PRETTY_NAME
├── defconfig                        Buildroot overrides (ARMv6, RPi kernel, rpi-firmware, Wi-Fi, ...)
├── README.md                        high-level target notes
├── fwup.conf                        full alloy task set (complete + upgrade.* + validate.* + rollback.* + status.*)
├── post-build.sh                    stage fwup_include/ + config.txt + cmdline-*.txt + autoboot-*.txt into $BINARIES_DIR
├── config.txt                       GPU firmware config (gpu_mem, dtoverlay=dwc2 + miniuart-bt + ramoops, ACT LED)
├── cmdline-a.txt                    root=/dev/mmcblk0p5 rootwait rootfstype=squashfs console=ttyAMA0,115200 console=ttyGS0
├── cmdline-b.txt                    root=/dev/mmcblk0p6 (same)
├── autoboot-a.txt                   sticky=BOOT-A, tryboot=BOOT-B
├── autoboot-b.txt                   sticky=BOOT-B, tryboot=BOOT-A
├── fwup_include/
│   ├── fwup-common.conf             partition offsets/counts + uboot-env block
│   └── provisioning.conf            empty include stub
├── linux/
│   └── linux-6.12.defconfig         full custom kernel defconfig (Kontron idiom; seeded from Nerves' rpi0)
│                                    (no MODULE_COMPRESS; brcmfmac + BT stack + hci_uart_bcm as =m;
│                                     USB gadget chain =y; SQUASHFS_XZ/ZLIB; PSTORE_RAM; SERIAL_DEV_BUS)
└── rootfs_overlay/
    ├── etc/
    │   ├── erlinit.config           -c ttyGS0, --pre-run-exec rngd + peripherals-init.sh,
    │   │                            -m /dev/mmcblk0p2:/boot:vfat:ro..., tmpfs /root + /var/log,
    │   │                            -r /srv/erlang, -n rpi0w-%s
    │   └── fw_env.config            /dev/mmcblk0 0x2000 0x2000 0x200 16
    └── sbin/
        └── peripherals-init.sh      mount pstore; btattach BCM43438 on /dev/ttyAMA1 (non-fatal)

toolchain/configs/
├── rpi0w_linux_x86_64_defconfig     crosstool-NG: ARMv6 / arm1176jzf-s / VFP / GCC 13
└── rpi0w_linux_aarch64_defconfig    same target, aarch64 build host
```

## 8. Status

| Area                                                         | State                                                                                                                                                           |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scaffolding + toolchain config                               | Files shipped                                                                                                                                                   |
| ARMv6 crosstool-NG toolchain                                 | Built + cached                                                                                                                                                  |
| Minimal SDK (Linux kernel + rootfs.squashfs)                 | Built                                                                                                                                                           |
| Firmware image (`.fw` / `.img`) with full alloy task set     | Built + flashed; `hello_grisp` boots to BEAM prompt on `ttyGS0`                                                                                                 |
| USB-OTG CDC-ACM serial console (`ttyGS0`)                    | Working                                                                                                                                                         |
| Ramoops / pstore                                             | Overlay staged, `CONFIG_PSTORE_RAM=y`, pstore mounted by `peripherals-init.sh`; warm-reboot capture not yet end-to-end validated on hardware                    |
| Wi-Fi (BCM43430)                                             | `brcmfmac` module loaded at boot via `peripherals-init.sh`, firmware blobs present, `wlan0` up with correct MAC; association with an AP not yet validated       |
| Bluetooth (BCM43438)                                         | `hci_uart` + `btbcm` + `bluetooth` modules loaded at boot, patchram `BCM43430A1.hcd` applied, `hci0` up; pairing / LE scan not yet validated                    |
| A/B update lifecycle (upgrade / validate / rollback)         | `fwup` task set implemented; tryboot + validate + rollback paths not yet exercised end-to-end on hardware                                                       |
| Update package (`BOOTSCHEME=RPI` plugin + `ops.fw` + `.tar`) | Not started                                                                                                                                                     |

## 9. References

**Internal:**

- [`../system_rpi0w/fwup.conf`](../system_rpi0w/fwup.conf): authoritative definition of the task set.
- [`../system_rpi0w/fwup_include/fwup-common.conf`](../system_rpi0w/fwup_include/fwup-common.conf): authoritative partition layout.
- [`../system_kontron-albl-imx8mm/fwup.conf`](../system_kontron-albl-imx8mm/fwup.conf): the template that drove the `uboot-env` schema and task vocabulary adopted here.
- [`../system_grisp2/fwup.conf`](../system_grisp2/fwup.conf): reference for `GRISP_FW_*` defines + MBR partitioning conventions.

**External:**

- [Raspberry Pi tryboot documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html#tryboot): `tryboot_a_b`, `autoboot.txt`, one-shot semantics.
- [fwup config reference](https://github.com/fwup-home/fwup/blob/main/docs/configuration.md): `mbr`, `uboot-environment`, `on-resource`, `fat_write`, `raw_write`, `reboot_param`.
- [Buildroot manual, external trees](https://buildroot.org/downloads/manual/manual.html#outside-br-custom): how `BR2_EXTERNAL` resolves `system_common` + `system_<target>`.
