# GRiSP Alloy (Linux RT / Buildroot)

Build tool for Linux-based embedded systems.

This repository uses `git lfs` to manage large files and `git-crypt` to
manage PKI secrets. Please install `git lfs` and `git-crypt` before cloning
this repository or checking this branch out.

If a system contains sensitive encrypted files, unlock PKI secrets before
building a production firmware image:

```sh
git-crypt unlock .pki-key
```

## Overview

`grisp_alloy` builds target firmware through a four-stage pipeline:

1. Build toolchain
2. Build SDK (Buildroot rootfs + host tools)
3. Build project artefact(s)
4. Build firmware/update/image artefacts

Main outputs in `artefacts/`:

- toolchain archive
- SDK archive
- project artefacts (`*.tgz`)
- firmware (`*.fw`)
- optional raw disk image(s) (`*.img`)
- optional update package (`*.tar`)

Supported targets in this repository:

- `grisp2`
- `kontron-albl-imx8mm`

External target bundles can add private `system_*`, `ramfs_*`, and
`toolchain/configs/*_defconfig` files without modifying this repository. Pass
external bundle roots with repeated `--external <DIR>` flags or set
`GRISP_ALLOY_EXTERNAL_PATH` to a colon-separated list:

```sh
GRISP_ALLOY_EXTERNAL_PATH=/path/to/private-bundle ./build-sdk.sh private-target
./build-firmware.sh --external /path/to/private-bundle private-target app
```

An external bundle root may contain multiple target systems and ramfs flavours:

```text
private-bundle/
  system_private-target/
  ramfs_private-target/
  toolchain/configs/private-target_linux_x86_64_defconfig
```

## Getting Started

### Prerequisites (Linux)

Install build dependencies:

```sh
sudo apt install build-essential libncurses5-dev \
    pv git bzr cvs mercurial subversion libc6:i386 unzip bc \
    bison flex gperf libncurses5-dev texinfo help2man \
    libssl-dev gawk libtool-bin automake lzip python3 mtools \
    u-boot-tools git-lfs keyutils qemu-user qemu-user-static \
    gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    binutils-x86-64-linux-gnu-dbg cpio
```

### Prerequisites (macOS)

macOS is supported via Vagrant VM execution:

```sh
brew install vagrant qemu
```

The scripts start the VM automatically when needed. Use `-P` to reprovision.

### Vagrant Variables (Useful Overrides)

You can control `Vagrantfile` behavior with environment variables:

- `VAGRANT_DEFAULT_PROVIDER`: force provider (for example `virtualbox`)
- `VAGRANT_DISABLE_NFS=1`: disable NFS path for VirtualBox and use default shared folders
- `VM_MEMORY`: VM RAM in MB (default `16384`)
- `VM_CORES`: VM CPU cores (default `8`)
- `VM_PRIMARY_DISK_SIZE`: primary VM disk size (for example `96GB`)
- `VM_CACHE_DISK_SIZE`: cache disk size in MB (default `10240`)

Examples:

```sh
VAGRANT_DEFAULT_PROVIDER=virtualbox VAGRANT_DISABLE_NFS=1 ./build-toolchain.sh grisp2
VM_MEMORY=8192 VM_CORES=4 ./build-sdk.sh grisp2
VM_PRIMARY_DISK_SIZE=96GB VM_CACHE_DISK_SIZE=20480 ./build-toolchain.sh -P grisp2
```

### Optional: Enable NFS (VirtualBox)

NFS can improve shared-folder performance, but VirtualBox needs a host-only network.

Requirements:

- A VirtualBox host-only adapter exists (with DHCP or static IP).
- `VAGRANT_DISABLE_NFS` is not set to `1`.

Run with NFS:

```sh
VAGRANT_DEFAULT_PROVIDER=virtualbox ./build-toolchain.sh -P grisp2
```

If you get:

```text
NFS requires a host-only network to be created.
```

create a host-only adapter in VirtualBox and reprovision (`-P`), or use:

```sh
VAGRANT_DEFAULT_PROVIDER=virtualbox VAGRANT_DISABLE_NFS=1 ./build-toolchain.sh grisp2
```

### First Successful Build

```sh
./build-toolchain.sh <TARGET>
./build-sdk.sh <TARGET>
./build-project.sh <TARGET> <PROJECT_DIR>
./build-firmware.sh <TARGET> <ARTEFACT_PREFIX_OR_PATH>
```

Example:

```sh
./build-toolchain.sh grisp2
./build-sdk.sh grisp2
./build-project.sh grisp2 samples/hello_grisp
./build-firmware.sh grisp2 hello_grisp
```

Target-specific end-to-end guides:

- [Build and Deploy GRiSP2](https://github.com/grisp/grisp_alloy/wiki/Build-and-Deploy-GRiSP2)
- [Build and Deploy Kontron AL/BL iMX8M Mini](https://github.com/grisp/grisp_alloy/wiki/Build-and-Deploy-Kontron-ALBL-iMX8MM)

## Build Pipeline

### 1. Build Toolchain

```sh
./build-toolchain.sh [OPTIONS] <TARGET>
```

Use `--print-config` to inspect the resolved toolchain defconfig without
building.

### 2. Build SDK

```sh
./build-sdk.sh [OPTIONS] <TARGET>
```

Common options:

- `-d | --debug`: print debug commands
- `-c | --clean`: clean and rebuild from scratch
- `-r | --rebuild`: rerun Buildroot stages for small changes
- `-p | --clean-package <PREFIX>`: rebuild specific Buildroot packages
- `-V | --force-vagrant`: run in Vagrant even on Linux
- `-P | --provision`: reprovision Vagrant VM
- `-K | --keep-vagrant`: keep VM running when script exits
- `--external <DIR>`: add an external bundle root
- `--enable-elixir` / `--disable-elixir`: include/exclude Elixir (enabled by default)
- `--enable-rust` / `--disable-rust`: include/exclude Cargo/rustc (disabled by default)

Erlang is always included because Alloy's build/firmware tools use OTP and Rebar.
Elixir and Rust support can be enabled or disabled independently. SDK archive
names include the enabled languages, for example `-erlang_rust.tar.gz` or
`-erlang_elixir_rust.tar.gz` (the default is `-erlang_elixir.tar.gz`).

For an SDK with Erlang and Rust support, with Elixir disabled:

```sh
./build-sdk.sh --disable-elixir --enable-rust grisp2
```

### 3. Build Project Artefact

```sh
./build-project.sh [OPTIONS] <TARGET> <PROJECT_DIR>
```

The project language determines the SDK requirements. Alloy searches installed
SDKs and archives in `artefacts/` for a match. If several SDKs match, it lists
them and stops. Add `--sdk-lang <LANG>` to require extra support; repeat the
option for additional languages. SDKs may include extra languages. Project
detection uses the main project type and does not inspect build hooks, so pass
`--sdk-lang rust` for an Erlang or Elixir project that builds a Rust NIF.

```sh
./build-project.sh grisp2 samples/hello_rust
./build-project.sh --sdk-lang rust grisp2 samples/hello_erlang_rust
```

Project archives use `<release>-<version>-<target>.tgz`, with `-<profile>` before
`.tgz` when `--profile` is not `default`. Rebuilding the same
release/version/target/profile replaces its archive.

Profiles are passed to the project builder: Rebar profiles for Erlang, Mix
environments for Elixir, and Cargo profiles for Rust. The default builds the
Rebar `default` profile, Mix `prod` environment, or Cargo `release` profile.

This packages a project tarball containing:

- `ALLOY-PROJECT` manifest
- `ALLOY-FS-PRIORITIES` (optional)
- `release/` (assembled BEAM or native payload)

Native applications install under `/srv/alloy/<instance>/bin/`. The first
project starts automatically; it is responsible for launching/supervising any
additional projects. A native primary runs as erlinit's foreground child, with
no ERTS/BEAM required in the image. Unexpected application exit reboots the
system; intentional shutdown sends SIGTERM before the graceful timeout.

If the project directory contains `.grisp_alloy_exclude`, its patterns are
passed to `rsync --exclude-from` when copying the project into the build area.

### 4. Build Firmware

```sh
./build-firmware.sh [OPTIONS] <TARGET> (ARTEFACT_PREFIX | ARTEFACT_PATH [--name NAME])...
```

Useful options:

- `-i | --generate-images`: also generate raw image files
- `-u | --generate-update`: also generate software update package
- `-o | --overlay <DIR>`: merge overlay into rootfs before packaging
- `-S | --security-pack <DIR>`: use security pack
- `-U | --sign-update`: sign update package (requires `--security-pack`)
- `-s | --serial <SERIAL>`: device serial (default `00000000`)
- `-p | --profile <PROFILE>`: security profile (default `default`)
- `-M | --provisioning-mode <MODE>`: target-declared provisioning mode
- `-R | --ramfs <CPIO_GZ>`: package an explicit initramfs artefact
- `-n | --name <NAME>` / `-v | --version <VER>`: override firmware metadata
- `--external <DIR>`: add an external bundle root

Project artefacts record the SDK used to build them, and firmware uses that
identity to select the SDK. Build all projects in a firmware with the same SDK.
If an artefact prefix matches multiple project archives, pass the exact `.tgz` path.

```sh
./build-firmware.sh -i grisp2 hello_grisp
```

Targets may declare firmware profiles, provisioning modes, SDK artefact
profiles, and initramfs policy in `system_<target>/crucible.sh`.

### Optional Ramfs Artefact

```sh
./build-ramfs.sh [OPTIONS] <FLAVOUR>
```

`build-ramfs.sh` builds `ramfs_<flavour>` from in-tree or external bundle
sources. Use `--print-buildroot` for a resolver smoke test that does not build.

### Security Pack Generation

```sh
./gen-secpack.sh [OPTIONS] <TARGET> <ABSOLUTE_OUTPUT_DIR>
```

Targets with `secpack.conf` can generate a generic development security pack.
Target-local `secpack.sh` hooks may add target-specific secure-boot material.
The output directory must be absolute and must not be inside the Alloy checkout
or target source tree.

### Firmware Flashing

```sh
./flash-firmware.sh [OPTIONS] <TARGET> <FIRMWARE_PREFIX_OR_PATH>
```

`flash-firmware.sh` is capability based. A target must provide `uuu.conf`; if it
does not, the command fails before SDK installation or hardware access with a
clear `Flashing not supported` error. Use `--dry-run` to inspect generated UUU
commands without flashing.

## Disk Images & Deployment

### Generate firmware + disk images

```sh
./build-firmware.sh -i <TARGET> <ARTEFACT>
```

### Write firmware to device with `fwup`

```sh
fwup -a -d <DEVICE> -i artefacts/<FIRMWARE>.fw -t complete
```

On macOS use `/dev/rdiskX` device names.

### Convert `.fw` to `.img`

```sh
rm -f out.img
touch out.img
fwup -a -d out.img -t complete -i artefacts/<FIRMWARE>.fw
```

### Inspect image partitions

```sh
fdisk -l artefacts/<FIRMWARE>.img
```

## Troubleshooting

Common failures:

- `SDK ... not found in artefacts`: run `./build-sdk.sh <TARGET>` first.
- `No artefact matching prefix ...`: build project first or pass full `.tgz` path.
- `Multiple artefacts found for prefix ...`: use a more specific prefix or explicit tarball path.
- `Missing release erts directory`: ensure the release includes ERTS (`include_erts`).
- `--sign-update/-U requires --security-pack/-S`: pass `-S <SECURITY_PACK_DIR>`.
- Vagrant environment drift after VM/config changes: rerun with `-P`.

VMware provider error (`vagrant-vmware-utility`) can be fixed by restarting the service:

```sh
sudo launchctl stop com.vagrant.vagrant-vmware-utility
sudo launchctl start com.vagrant.vagrant-vmware-utility
```

## Advanced Use Cases

- [Run Multiple VMs with grisp_supervisor](https://github.com/grisp/grisp_alloy/wiki/Run-Multiple-VMs-with-grisp_supervisor)
- [Customize core isolation for critical RT applications](https://github.com/grisp/grisp_alloy/wiki/Customize-core-isolation-for-critical-RT-applications)

## Platform Source-of-Truth Notes

Keep these in-repo READMEs aligned with implementation:

- `system_grisp2/README.md`
- `system_kontron-albl-imx8mm/README.md`
