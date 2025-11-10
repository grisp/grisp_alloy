# GRiSP Alloy

Build tool for Linux-based embedded systems.

This repository uses `git lfs` to manage large files and `git-crypt` to
manage PKI secrets. Please install `git lfs` and `git-crypt` before cloning
this repository or checking this branch out.

If a system contains sensitive encripted files, you need to unlock the PKI
secrets to building an actual firmware image using:

```sh
git-crypt unlock .pki-key
```

after you received the key file from somewhere. You don't need to do that
again, the de- and encryption is handled automatically from now on.


## Prerequisites

### Linux

Install the following packages:

```sh
sudo apt install build-essential libncurses5-dev \
    pv git bzr cvs mercurial subversion libc6:i386 unzip bc \
    bison flex gperf libncurses5-dev texinfo help2man \
    libssl-dev gawk libtool-bin automake lzip python3 mtools \
    u-boot-tools git-lfs keyutils qemu-user qemu-user-static \
    gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    binutils-x86-64-linux-gnu-dbg
```


### OSX

OSX is not supported natively, a Vagrant VM is used as well as qemu to create
the cache disk in vmdk format:

```sh
brew install vagrant qemu
```

The scripts should handle the setup and startup of the vagrant VM,
but if anything goes wrong you can try to manually delete the vagrant image:

```sh
vagrant destroy
```

and or manually start the VM

```sh
vagrant up
```

## Build Toolchain

```sh
./build-toolchain.sh <TARGET_NAME>
```

e.g.

```sh
./build-toolchain.sh grisp2
```


## Build SDK

The toolchain must have been built previously.

```sh
./build-sdk.sh <TARGET_NAME>
```

e.g.

```sh
./build-sdk.sh grisp2
```


## Build Project Artefact

Both the toolchain and the SDK must have been built previously.

```sh
./build-project.sh [-p <PROFILE>] <TARGET_NAME> <PROJECT_DIRECTORY>
```

This builds the project using plugins (Erlang/Elixir) and packages a tarball
in `artefacts/` containing:

- ALLOY-PROJECT: manifest with project and target metadata
- ALLOY-FS-PRIORITIES: optional SquashFS priority list (may be empty)
- release/: OTP release directory

Tarball name: `<rel_name>-<rel_ver>-<target>[-<profile>].tgz`

e.g.

```sh
./build-project.sh grisp2 samples/hello_grisp
```

## Build Firmware Update

Builds a firmware from one or more pre-built project artefacts. Each artefact
can be a full path to a `.tgz` file or a name prefix resolved from `artefacts/`.


```sh
./build-firmware.sh [-i] [-s SERIAL] [-o OVERLAY_DIR] [-n FIRMWARE_NAME] <TARGET_NAME> (ARTEFACT_PREFIX | ARTEFACT_PATH [--name NAME])...
```

Examples:

```sh
# Single project
./build-firmware.sh grisp2 artefacts/hello_grisp-0.1.0-grisp2.tgz
# Multiple projects with explicit destination names
./build-firmware.sh grisp2 hello_grisp --name alpha hello_elixir --name beta
# Multiple projects with overlay
./build-firmware.sh -o samples/overlay grisp2 hello_grisp hello_elixir
```

Behavior:

- Each project is staged under `/srv/alloy/<name>` in the target filesystem.
  The `<name>` defaults to the project app name or can be set with `--name`.
- A stable symlink `/srv/erlang` points to the first project's directory.
- alloy-firmware.json is generated describing all deployed projects (root,
  app_ver, rel_ver, type, profile, erts_ver, vcs) and SDK/target metadata.
- The script validates that each artefact matches the requested target and SDK
  versions and architecture.
- Destinations must be unique; the build fails if two projects use the same
  name or the destination already exists in the overlay.
- When using the `-i` flag, raw disk images are generated in addition to the
  firmware file.

### Using a Security Pack

A security pack is an external repository holding all security-related material
(keys, certificates, and helper scripts). It is consumed by `grisp_alloy` to:
- generate a device/profile security overlay merged into the firmware rootfs
- sign software update packages for on-device signature validation
- enable mTLS and client certificate validation in artefact_server

Required contents in the security pack:
- `grisp_updater/verification/`
  - `signature_cert.pem` — certificate chain used by devices to verify update signatures
  - `signature_key.pem` — private key used to sign software update packages
- `devices`
  - `devices.chain.pem` - certification chain for all devices
- Root script `secpack` exposing command `generate-overlay`:
  - `secpack generate-overlay <output-dir> <serial> [profile]`
    - Creates an overlay with security data for the given device serial and optional profile (`default` if omitted)

Usage with `build-firmware.sh`:
- `-S | --security-pack <DIR>`: path to the security pack
  - Automatically runs `secpack generate-overlay` and merges the result (after any `--overlay`)
- `-p | --profile <NAME>`: select security profile (default: `default`)
- `-U | --sign-update`: sign the software update package using `grisp_updater_tools` with the signing key from the security pack
  - Requires `signature_key.pem`; build fails early if missing when `-U` is provided
- `-s | --serial <SERIAL>`: device serial used by the security pack for device-specific material

Examples:

```sh
# Generate security overlay (default profile) and build firmware
./build-firmware.sh -S /path/to/security-pack -s 00000001 grisp2 hello_grisp

# Build and sign the update package using the secpack signing key
./build-firmware.sh -u -U -S /path/to/security-pack -s 00000001 -p dev grisp2 hello_grisp
```

### Burn Firmware

#### To a device

On MacOS, the device `rdiskX` should be used instead of `diskX`.

First the device need to be unmounted:

```sh
diskutil unmountDisk <SD_CARD_DEVICE> # MacOS
unmount <SD_CARD_DEVICE> # Linux
```

e.g.

```sh
diskutil unmountDisk /dev/rdisk4 # MacOS
unmount /dev/sdc # Linux
```

Then the firmware can be burnt, either with `fwup`:

```sh
fwup -a -d <SD_CARD_DEVICE> -i <FIRMWARE_FILE> -t complete
```

e.g.

```sh
fwup -a -d /dev/sdc -i artefacts/hello_grisp-0.1.0-grisp2.fw -t complete # Linux
```

or for image firware, directly copy it to the device:

```sh
sudo cp <FIRMWARE_IMAGE> <SD_CARD_DEVICE>
```

e.g.

```sh
sudo cp artefacts/grisp2.img /dev/rdisk4 # MacOS
```

Due to macOS having some trouble with the encrypted partitions there
might be a window popping up asking what to do. On disk insertion you
should use 'Initialize' (and close the window which then pops up) and
after writing the SD card use 'Eject'.


#### As an image

This is to generate a firmware image from a `fwup` firmware.
The image file need to exists but be empty.

```sh
rm -f <IMAGE_FILE>
touch <IMAGE_FILE>
fwup -a -d <IMAGE_FILE> -t complete -i <FIRMWARE_FILE>
```

e.g.

```sh
rm -f hello_grisp-0.1.0-grisp2.img
touch hello_grisp-0.1.0-grisp2.img
fwup -a -d hello_grisp-0.1.0-grisp2.img -t complete -i hello_grisp-0.1.0-grisp2.fw
```


### Development

During development there is multiple paramteres to these script that could  be
useful.

Common parameters for all scripts:

 - `-d` : Print all the commands on the console for debugging purposes.
 - `-c` : This flag cleaup everithing and start the process from scratch.
 - `-V` : This flag make the script force the use of a Vagrant VM on Linux.
 - `-P` : When using a Vagrant VM, this will force a provision of the VM;
          this is useful when modifying the scripts to be sure the changes are
          replicated into the VM.
 - `-K` : Keep the Vagrant VM running after exiting the script; this allows
          connecting to the VM with ssh and make the startup faster if the VM
          is already running.

`build-sdk.sh` specific parameters:

 - `-r` : Re-run buildroot without cleaning up anything; this is usefull when
          some small changes were made that would not require a full build from
          scratch.


#### Vagrant Options

Vagrant VM can be tweaked by setting some environment variables:

 - `VM_PRIMARY_DISK_SIZE`: Size of the primary disk, if not specified Vagrant will use its internally defined default.
 - `VM_MEMORY`: Memory allocated to the VM in MiB as an integer, default is 16384
 - `VM_CORES`: Numbers of cores allocated to the VM, defauklt is 8
 - `VM_CACHE_DISK_SIZE`: Size of the cache disk in MiB as an integer, default is 10240.


#### Inspecting a firmware image

##### Inspect Image Partitions

```sh
fdisk -l <IMAGE_FILE>
```

e.g.

```sh
fdisk -l artefacts/hello_grisp-0.1.0-grisp2.img
```


##### Mount an Image Partition

You need to know the offset of the partition you want to mount.
You can get it by inspecting the partition as described before and multiplying
the offset given by fdisk byt the block size. Then you can do:

```sh
sudo mount -o loop,offset=<PARTITION_OFFSET> <IMAGE_FILE> <MOUNT_DIRECTORY>
```

e.g.

```sh
$ mkdir -p /tmp/hello_grisp_grisp2_disk
$ fdisk -l artefacts/hello_grisp-0.1.0-grisp2.img
Disk artefacts/hello_grisp-0.1.0-grisp2.img: 311.13 MiB, 326238208 bytes, 637184 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x00000000

Device                                  Boot  Start     End Sectors  Size Id Type
artefacts/hello_grisp-0.1.0-grisp2.img1 *     20480   49151   28672   14M  c W95 FAT32 (LBA)
artefacts/hello_grisp-0.1.0-grisp2.img2       63488  350207  286720  140M 83 Linux
artefacts/hello_grisp-0.1.0-grisp2.img3      350208  636927  286720  140M 83 Linux
artefacts/hello_grisp-0.1.0-grisp2.img4      636928 1685503 1048576  512M 83 Linux
# Mounting partition 0 with offset 20480*512=10485760
$ sudo mount -o loop,offset=10485760 artefacts/hello_grisp-0.1.0-grisp2.img /tmp/hello_grisp_grisp2_disk
$ ls -la /tmp/hello_grisp_grisp2_disk
total 3300
drwxr-xr-x  3 root root   16384 Jan  1  1970 .
drwxrwxrwt 14 root root    4096 Jul  8 16:46 ..
drwxr-xr-x  3 root root     512 Jan  1  1980 loader
-rwxr-xr-x  1 root root   38342 Jan  1  1980 oftree
-rwxr-xr-x  1 root root 3319104 Jan  1  1980 zImage.a
$ sudo umount /tmp/hello_grisp_grisp2_disk
# Mounting partition 1 with offset 63488*512=32505856
$ sudo mount -o loop,offset=32505856 artefacts/hello_grisp-0.1.0-grisp2.img /tmp/hello_grisp_grisp2_disk
$ ls -la /tmp/hello_grisp_grisp2_disk
total 12
drwxr-xr-x 19 sylane sylane   233 ene 27 19:48 .
drwxrwxrwt 28 root   root   12288 ene 28 16:04 ..
drwxr-xr-x  2 root   root     271 sep  1 22:26 bin
drwxr-xr-x  2 root   root       3 sep  1 22:26 data
drwxr-xr-x  4 root   root      48 sep  1 22:26 dev
drwxr-xr-x  5 root   root     301 sep  1 22:26 etc
drwxr-xr-x  4 root   root     807 sep  1 22:26 lib
lrwxrwxrwx  1 root   root       3 sep  1 22:26 lib32 -> lib
drwxr-xr-x  2 root   root       3 sep  1 22:26 media
drwxr-xr-x  3 root   root      27 sep  1 22:26 mnt
drwxr-xr-x  2 root   root       3 sep  1 22:26 opt
drwx------  2 root   root       3 sep  1 22:26 root
drwxr-xr-x  2 root   root       3 sep  1 22:26 run
drwxr-xr-x  2 root   root     306 sep  1 22:26 sbin
drwxrwxr-x  3 root   root      29 ene 27 19:48 srv
drwxr-xr-x  2 root   root       3 sep  1 22:26 sys
drwxrwxrwt  2 root   root       3 sep  1 22:26 tmp
drwxr-xr-x  6 root   root      75 sep  1 22:26 usr
drwxr-xr-x  9 root   root      97 sep  1 22:26 var
$ sudo umount /tmp/hello_grisp_grisp2_disk
```


##### Use QEMU with Image Partition

```sh
sudo apt install qemu-system-arm qemu-user-static binfmt-support
sudo mkdir -p /tmp/grisp_p1_ro /tmp/grisp_p1_upper /tmp/grisp_p1_work /tmp/grisp_p1_rw
sudo systemctl daemon-reload
sudo mount -o loop,offset=32505856 artefacts/hello_grisp-0.1.0-grisp2.img /tmp/grisp_p1_ro
sudo mount -t overlay overlay -o lowerdir=/tmp/grisp_p1_ro,upperdir=/tmp/grisp_p1_upper,workdir=/tmp/grisp_p1_work /tmp/grisp_p1_rw
sudo cp /usr/bin/qemu-arm-static /tmp/grisp_p1_rw/usr/bin/
sudo mount -t proc proc /tmp/grisp_p1_rw/proc
sudo mount --rbind /sys /tmp/grisp_p1_rw/sys
sudo mount --rbind /dev /tmp/grisp_p1_rw/dev
sudo chroot /tmp/grisp_p1_rw /usr/bin/qemu-arm-static /bin/ash
PATH=/usr/sbin:/usr/bin:/sbin:/bin ROOTDIR=/srv/erlang BINDIR=/srv/erlang/erts-16.0.1/bin RELEASE_SYS_CONFIG=/srv/erlang/releases/0.0.1/sys RELEASE_ROOT=/srv/erlang RELEASE_TMP=/tmp LANG=en_US.UTF-8 LANGUAGE=en ERL_INETRC=/etc/erl_inetrc /usr/bin/qemu-arm-static /srv/erlang/erts-16.0.1/bin/erlexec -config /srv/erlang/releases/0.0.1/sys.config -boot /srv/erlang/releases/0.0.1/no_dot_erlang -args_file /srv/erlang/releases/0.0.1/vm.args -boot_var RELEASE_LIB /srv/erlang/lib
```


### Troubleshooting

#### Extract Toolchain Kernel Header Version

```sh
tar -xOf grisp_toolchain_arm_unknown_linux_gnueabihf-*.tar.xz arm-unknown-linux-gnueabihf/arm-unknown-linux-gnueabihf/sysroot/usr/include/linux/version.h | awk '/^#define[[:space:]]+LINUX_VERSION_CODE[[:space:]]+/ { a = $3 / 65536; b = ($3 % 65536) / 256; c = $3 % 256; printf "%d.%d.%d\n", a, b, c; exit }'
```


#### VMware errors

If you get this error when starting a VM:

```
An error was encountered while generating the current list of
available VMware adapters in use on this system.
  Get http://localhost:49191/api/vmnet: GET http://localhost:49191/api/vmnet giving up after 5 attempts
```

you need to restart the vagrant-vmware-utility service:
```sh
$ sudo launchctl stop com.vagrant.vagrant-vmware-utility
$ sudo launchctl start com.vagrant.vagrant-vmware-utility
```

If you get a disk resize error during the first VM setup like:

```sh
$ vagrant up
Bringing machine 'default' up with 'vmware_desktop' provider...
==> default: Cloning VMware VM: 'bento/ubuntu-24.04'. This can take some time...
==> default: Checking if box 'bento/ubuntu-24.04' version '202502.21.0' is up to date...
==> default: Verifying vmnet devices are healthy...
==> default: Preparing network adapters...
Disk not resized because snapshots are present! Vagrant can
not resize a disk if snapshots exist for a VM. If you wish to resize
disk please remove snapshots associated with the VM.

Path: .../grisp_alloy/.vagrant/machines/default/vmware_desktop/a3a60172-8195-4235-a1e9-f0011657068a/disk-000055.vmdk
```

You need to cleanup the snapshots and reload, then resize the disk in the gest.

On the host:

```sh
vagrant halt -f
vagrant cap provider delete_all_snapshots --target default
vagrant reload
vagrant ssh
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT   # sdb should now be ~96G
sudo growpart /dev/sdb 3
sudo pvresize /dev/sdb3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
df -h /
```
