# Build architecture

Cross-cutting design reference for the four-stage build pipeline. The
top-level [`README.md`](../README.md) documents the day-to-day commands;
this file explains the *why* behind each stage and what actually ends up
on disk between them.

## 1. The four scripts in one picture

```
build-toolchain.sh    -> /opt/.../toolchain: cross-compiler only
                         (glibc, gcc, binutils, kernel headers)
       |
       v
build-sdk.sh          -> /opt/<sdk>/<target>/<ver>/host/   (host-side tools)
                         /opt/<sdk>/<target>/<ver>/target/ (target sysroot)
                         _build/system/build/images/        (kernel, DTBs, rootfs.squashfs)
                         artefacts/grisp_alloy_sdk-*.tar.gz (packaged SDK)
       |
       v
build-project.sh      -> artefacts/<name>-project.tar
                         (user's OTP release, cross-compiled against the SDK)
       |
       v
build-firmware.sh     -> artefacts/<name>.fw
                         (rootfs.squashfs + project release + fwup.conf
                          packaged into a flashable firmware blob)
```

Each stage produces a frozen artefact the next stage consumes. The SDK
stage is the expensive one (a clean rebuild is in the ~2 h range, most
of that is Buildroot compiling Erlang, OpenSSL, and BusyBox); the other
three stages are minutes.

## 2. What `/opt/grisp_alloy_sdk/` actually contains

After `build-sdk.sh` runs, the SDK install root looks roughly like this
(`<sdk-ver>` e.g. `0.2.0`, `<target>` e.g. `rpi0w`, `<target-ver>` e.g.
`0.1.0`):

```
/opt/grisp_alloy_sdk/<sdk-ver>/<target>/<target-ver>/
    host/
        bin/
            armv6-unknown-linux-gnueabihf-gcc   <- cross-compiler
            armv6-unknown-linux-gnueabihf-strip
            erlc                                <- HOST Erlang compiler
            rebar3                              <- Host build tool for OTP releases
            mksquashfs                          <- Used by fwup to assemble rootfs
            fwup                                <- Firmware image builder
            ...
        lib/erlang/                             <- Host-side Erlang/OTP installation
        include/
    target/                                     <- Target sysroot
        usr/lib/erlang/                         <- TARGET Erlang/OTP (ARMv6 binaries)
        usr/lib/libssl.so.*                     <- Target shared libs the BEAM links against
        ...
    VERSIONS
    GIT
    defconfig
    .config                                     <- Buildroot's merged kernel+userspace config
    images/                                     <- kernel zImage, DTBs, rootfs.squashfs
    staging/
```

Three things worth noticing:

1. **The SDK is a toolkit, not just a cross-compiler.** The
   `build-toolchain.sh` stage produces the cross-compiler; the SDK stage
   layers on top of that every userspace tool needed to build and
   package a GRiSP Alloy project: Erlang, rebar3, fwup, mksquashfs,
   squashfs-tools, fw_env tools. That's the point of the tarball in
   `artefacts/grisp_alloy_sdk-*.tar.gz`: a single archive that, once
   unpacked, lets `build-project.sh` and `build-firmware.sh` run with
   no further dependency installs.

2. **Two Erlangs are produced in the same Buildroot run**:

   | Erlang                | Location in SDK                                | Used for                              |
   | --------------------- | ---------------------------------------------- | ------------------------------------- |
   | Host Erlang           | `host/bin/erlc`, `host/lib/erlang/`            | `build-project.sh` compiles user code |
   | Target Erlang/OTP     | `target/usr/lib/erlang/` (rolled into rootfs)  | runs on device as PID 1 via erlinit   |

   Both must come out of the same Buildroot run so their OTP major
   versions stay in lockstep. A user project built with `host/bin/rebar3`
   produces BEAM files that must load on `target/usr/lib/erlang/erts-*/bin/beam.smp`
   at runtime. Different majors would break NIF ABI, BEAM file format,
   or stdlib APIs.

3. **The `target/` tree becomes `rootfs.squashfs`.** Buildroot's
   `target-finalize` step sanitises `target/` (strips binaries, removes
   `/usr/share/man`, etc.) and then `mksquashfs` packs the whole thing
   into `images/rootfs.squashfs`. That squashfs goes straight into
   `fwup.conf` as `${GRISP_SYSTEM}/images/rootfs.squashfs` at firmware
   build time.

## 3. Why Erlang is built in `build-sdk.sh`, not `build-project.sh`

Three reasons:

- **ABI lockstep with target userspace.** The BEAM on the device links
  against `libpthread`, `libcrypto`, `libssl`, `libstdc++` from the
  target sysroot. Those libraries are produced by the same Buildroot
  run that produces Erlang, so they're guaranteed to match. If Erlang
  were built at project time, you'd need to recreate the same sysroot
  in isolation, or risk ABI drift the next time a library bumped.

- **Host `erlc`/`rebar3` must match target OTP version.** See the
  "two Erlangs" point above: locking both versions behind one SDK
  build is how we guarantee a user's `.beam` files load on the device.

- **GRiSP OTP is a patched Erlang fork, not stock.** Buildroot applies
  `system_common/patches/buildroot/0007-erlang-support-OTP-21-28.patch`
  (and any target-specific patches) before building. That patching is
  part of what "the SDK" means here. Doing it at project time would mean
  re-patching per-project, which defeats the point of a reusable SDK.

## 4. Kernel, rootfs, and firmware metadata: where each lives

The SDK stage produces the on-device bits; the firmware stage packages
them:

| Artefact                 | Produced by      | Consumed by               |
| ------------------------ | ---------------- | ------------------------- |
| `zImage` / `Image`       | Buildroot kernel | fwup (boot partition)     |
| `*.dtb` / `*.dtbo`       | Buildroot kernel | fwup (boot partition)     |
| `rootfs.squashfs`        | Buildroot        | fwup (A/B rootfs slots)   |
| `bootcode.bin`, `start.elf`, etc. | `BR2_PACKAGE_RPI_FIRMWARE` (rpi0w/grisp2) | fwup (boot partition) |
| `cmdline-a.txt` / `-b.txt` | `system_<target>/post-build.sh` (stages them into `images/`) | fwup (boot partition) |
| `autoboot-a.txt` / `-b.txt` | same              | fwup (tryboot logic)      |
| `u-boot.bin` / `flash.bin` | Buildroot U-Boot (kontron) | fwup (bootloader partition) |
| `uboot-env` | fwup itself (template in `fwup.conf`) | U-Boot / userspace metadata |
| Project release tarball | `build-project.sh` | fwup (app payload)         |

The `fwup.conf` in each `system_<target>/` declares exactly which
files go where. `build-firmware.sh` invokes the host `fwup` binary
(from the SDK's `host/bin/`) to assemble the `.fw`.

## 5. Checkpoints and resumability

`build-sdk.sh` uses a simple checkpoint file per step:

```
_build/system/checkpoints/
    prepare_environment
    checkout_source_code
    prepare_buildroot
    run_buildroot
```

Each empty marker file signals "this step completed". On the next run:

- `-r` / `--rebuild` removes only `prepare_buildroot` and `run_buildroot`,
  so you re-run Buildroot without re-extracting the tarball or wiping
  `_build`. Safe for small package changes.
- `-c` / `--clean` removes the whole checkpoint dir, so
  `prepare_environment` runs and wipes `_build/system/build` entirely.
  Use whenever the kernel config or Buildroot defconfig changes
  non-trivially.
- `-p <prefix>` cleans a specific package's build dir (`build/<prefix>*`)
  and is typically combined with `-r` for "rebuild just this package".

`build-project.sh` and `build-firmware.sh` do not use checkpoints
because they're fast enough that re-running from scratch is the simpler
contract.

## 6. The Vagrant wrapper (macOS / non-Linux hosts)

Buildroot requires Linux. On macOS, `build-sdk.sh` detects the host and
re-enters the same command inside a Vagrant-managed Ubuntu VM
(`Vagrantfile`). Everything between "host script invocation" and
"Buildroot running" is wrapper plumbing. The key points:

- Host `system_<target>/` directories are **copied** into the VM via
  Vagrant's `file` provisioner on `vagrant up` or `vagrant provision`.
  They're not live-synced. If you edit `system_rpi0w/defconfig` on the
  host and want that to reach the VM, pass `-P` so `build-sdk.sh` runs
  `vagrant provision` before the build.
- `artefacts/` *is* a live synced folder (NFS on Linux hosts, vboxsf
  when `VAGRANT_DISABLE_NFS=1` is set). That's why the `.fw` file
  appears on the host the moment Buildroot writes it in the VM.
- The VM has the SDK installed under `/opt/grisp_alloy_sdk/` so
  follow-up `build-project.sh` / `build-firmware.sh` runs don't need
  to re-unpack the SDK tarball.

Net effect for a macOS user: each `build-*.sh` invocation is a thin
wrapper that round-trips the command into the VM. The shell prompt on
the host is your interface; the work happens inside the VM.

## 7. Further reading

- Per-target design docs: [`README.md`](./README.md) (index)
- Porting a new target: [`porting-notes.md`](./porting-notes.md)
- The SDK package script that drives `make-sdk.sh` assertions:
  `system_common/scripts/make-sdk.sh`
- Buildroot's own docs: https://buildroot.org/downloads/manual/manual.html
