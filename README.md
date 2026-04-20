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

**Table of contents**

- [Overview](#overview)
- [Getting Started](#getting-started)
  - [Prerequisites (Linux)](#prerequisites-linux)
  - [Prerequisites (macOS)](#prerequisites-macos)
  - [Vagrant Variables (Useful Overrides)](#vagrant-variables-useful-overrides)
  - [Optional: NFS for `artefacts/` (VirtualBox)](#optional-nfs-for-artefacts-virtualbox)
  - [First Successful Build](#first-successful-build)
- [Build Pipeline](#build-pipeline)
  - [1. Build Toolchain](#1-build-toolchain)
  - [2. Build SDK](#2-build-sdk)
  - [3. Build Project Artefact](#3-build-project-artefact)
  - [4. Build Firmware](#4-build-firmware)
- [Disk Images & Deployment](#disk-images-deployment)
  - [Generate firmware + disk images](#generate-firmware-disk-images)
  - [Write firmware to device with `fwup`](#write-firmware-to-device-with-fwup)
  - [Convert `.fw` to `.img`](#convert-fw-to-img)
  - [Inspect image partitions](#inspect-image-partitions)
- [Troubleshooting](#troubleshooting)
- [Advanced Use Cases](#advanced-use-cases)
- [Platform Source-of-Truth Notes](#platform-source-of-truth-notes)

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
brew install --cask virtualbox
```

The scripts start the VM automatically when needed. Use `-P` to reprovision.

**Troubleshooting (macOS / VirtualBox):** On Ruby 3.2+, run **`./scripts/vagrant/patch-vagrant-vbguest-ruby3.sh`**
on the host once (after **`vagrant plugin install vagrant-vbguest`**) so the gem stops using the
removed **`File.exists?`** API. For a quick environment snapshot, run **`./scripts/vagrant/vagrant-diagnose.sh --compact`**;
for a full report (for example when opening an issue), run **`./scripts/vagrant/vagrant-diagnose.sh`**.
The `Vagrantfile` sets `vagrant-vbguest` **`auto_update` to false** by default on Ruby 3.2+ so an
unpatched gem does not hit the broken path; after patching, you can enable Guest Additions updates
with **`VAGRANT_VBGUEST_AUTO_UPDATE=1 vagrant up`**.

Vagrant-only helpers live under **`scripts/vagrant/`**. Builds invoked via `vagrant exec` use
**`GLB_VAGRANT_REPO_ROOT`** (default **`/vagrant`** on VirtualBox with rsync), so inside the VM
the same scripts are at **`/vagrant/scripts/vagrant/`** (for example
`/vagrant/scripts/vagrant/vagrant-diagnose.sh`). Use that path when you need the tree that stays
in sync with the host; the provisioned copy at `/home/vagrant/scripts/` updates when you run
`vagrant provision` or `./build-*.sh -P`.

### Vagrant Variables (Useful Overrides)

You can control `Vagrantfile` behavior with environment variables:

- `VAGRANT_DEFAULT_PROVIDER`: force provider (for example `virtualbox`)
- `VAGRANT_VB_CACHE_STORAGectl`, `VAGRANT_VB_CACHE_PORT`, `VAGRANT_VB_CACHE_DEVICE`: VirtualBox
  cache-disk attachment. If **`VAGRANT_VB_CACHE_STORAGectl`** is unset, the name comes from the box
  **OVF** under **`~/.vagrant.d/boxes/`**, then from **`storagecontrollername0`** in **`showvminfo`**.
  On **`vagrant up`** / **`reload`**, if the box is not cached yet, the **`Vagrantfile` runs
  **`vagrant box add`** once so the OVF exists (disable with **`VAGRANT_SKIP_BOX_PREFETCH=1`**). You
  can still set **`VAGRANT_VB_CACHE_STORAGectl`** to override. Port / device default to **`1`** /
  **`0`**.
- `VAGRANT_DISABLE_NFS=1`: disable NFS path for VirtualBox and use default shared folders
- `GLB_VAGRANT_REPO_ROOT`: repo path inside the guest for `vagrant exec` (default **`/vagrant`**;
  use **`/home/vagrant`** on VMware if there is no `/vagrant` mount)
- `VAGRANT_VBGUEST_AUTO_UPDATE=1`: turn `vagrant-vbguest` automatic Guest Additions updates back on
- `VAGRANT_VIRTUALBOX_SYNC_TYPE`: `virtualbox` (vboxsf) or `rsync` (on **Apple Silicon** Macs,
  VirtualBox often defaults to **rsync**; Intel-based Macs may use either); with rsync, macOS syncs
  `./artefacts/` via **`scripts/common.sh`**
- `VAGRANT_USE_NFS`, `VAGRANT_DISABLE_NFS`: NFS for `artefacts/` on VirtualBox (see subsection below)
- `VM_MEMORY`: VM RAM in MB (default `16384`)
- `VM_CORES`: VM CPU cores (default `8`)
- `VM_PRIMARY_DISK_SIZE`: primary VM disk size (for example `96GB`)
- `VM_CACHE_DISK_SIZE`: cache disk size in MB (default `10240`)

Examples:

```sh
# VirtualBox on Linux: `VAGRANT_DISABLE_NFS=1` skips the NFS-backed `artefacts/` sync (no host-only adapter).
VAGRANT_DEFAULT_PROVIDER=virtualbox VAGRANT_DISABLE_NFS=1 ./build-toolchain.sh grisp2
# macOS + VirtualBox: omit `VAGRANT_DISABLE_NFS=1` (typical on Apple Silicon and Intel; see NFS/rsync above).
VM_MEMORY=8192 VM_CORES=4 ./build-sdk.sh grisp2
VM_PRIMARY_DISK_SIZE=96GB VM_CACHE_DISK_SIZE=20480 ./build-toolchain.sh -P grisp2
```

### Optional: NFS for `artefacts/` (VirtualBox)

NFS can be faster than `vboxsf` but needs a **host-only network** in VirtualBox. Set
`VAGRANT_USE_NFS=1` (and do not force `rsync` sync). If you see `NFS requires a host-only network`,
either add that adapter in VirtualBox or stay on the default **rsync** (common on **Apple Silicon**
Macs) or **VirtualBox shared folders** (other hosts, including Intel-based Macs).

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
./build-toolchain.sh [-h] [-d] [-c] [-V] [-P] [-K] <TARGET>
```

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

### 3. Build Project Artefact

```sh
./build-project.sh [OPTIONS] <TARGET> <PROJECT_DIR>
```

This packages a project tarball containing:

- `ALLOY-PROJECT` manifest
- `ALLOY-FS-PRIORITIES` (optional)
- `release/` (OTP release)

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
- `-n | --name <NAME>` / `-v | --version <VER>`: override firmware metadata

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
