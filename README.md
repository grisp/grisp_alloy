# Grisp Linux Builder

Building a firmware require a SDK, and a SDK requires a toolchain.


## Prerequisites

### Linux

Install the following packages:

```sh
$ sudo apt install build-essential libncurses5-dev \
                pv git bzr cvs mercurial subversion libc6:i386 unzip bc \
                bison flex gperf libncurses5-dev texinfo help2man \
                libssl-dev gawk libtool-bin automake lzip python3
```

### OSX

OSX is not supported natively, a Vagrant VM is used.
The scripts should handle the setup and startup of the vagrant VM,
but if anything goes wrong you can try to manually delete the vagrant image:

```sh
$ vagrant destroy
```

## Build Toolchain

```sh
$ ./build-toolchain.sh TARGET_NAME
```

e.g.

```sh
$ ./build-toolchain.sh grisp2
```


## Build SDK

The toolchain must have been built previously.

```sh
$ ./build-sdk.sh TARGET_NAME
```

e.g.

```sh
$ ./build-sdk.sh grisp2
```

## Build Firware Update

Both the toolchain and the SDK must have been built previously.

```sh
$ ./build-firmware.sh TARGET_NAME ERLANG_PROJECT_DIRECTORY [REBAR3_PROFILE]
```

e.g.

```sh
$ ./build-firmware.sh grisp2 samples/hello_grisp
```

In addition to the firmware, an image file can be generated:

```sh
$ ./build-firmware.sh -i TARGET_NAME ERLANG_PROJECT_DIRECTORY [REBAR3_PROFILE]
```

e.g.

```sh
$ ./build-firmware.sh -i grisp2 samples/hello_grisp
```

Keep in mind that image file could be a lot bigger than the firmware.


### Burn Firmware


#### To a device

```sh
$ fwup -a -d SD_CARD_DEVICE -i FIRMWARE_FILE -t complete
```

e.g.

```sh
$ fwup -a -d /dev/sdc -i hello_grisp-0.1.0-grisp2.fw -t complete
```


#### As an image

The image file need to exists but be empty.

```sh
$ rm -f IMAGE_FILE
$ touch IMAGE_FILE
$ fwup -a -d IMAGE_FILE -t complete -i FIRMWARE_FILE
```

e.g.

```sh
$ rm -f hello_grisp-0.1.0-grisp2.img
$ touch hello_grisp-0.1.0-grisp2.img
$ fwup -a -d hello_grisp-0.1.0-grisp2.img -t complete -i hello_grisp-0.1.0-grisp2.fw
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


#### Inspecting a firmware image

##### Inspect Image Partitions

```sh
$ fdisk -l IMAGE_FILE
```

e.g.

```sh
$ fdisk -l hello_grisp-0.1.0-grisp2.img
```

##### Mount an Image Partition

You need to know the offset of the partition you want to mount.
You can get it by inspecting the partition as described before and multiplying
the offset given by fdisk byt the block size. Then you can do:

```sh
$ sudo mount -o loop,offset=PARTITION_OFFSET IMAGE_FILE MOUNT_DIRECTORY
```

e.g.

```sh
$ mkdir -p /tmp/hello_grisp_disk
$ fdisk -l hello_grisp-0.1.0-grisp2.img
Disk hello_grisp-0.1.0-grisp2.img: 311,1 MiB, 326238208 bytes, 637184 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x00000000

Device                        Boot  Start     End Sectors  Size Id Type
hello_grisp-0.1.0-grisp2.img1 *      4096   32767   28672   14M  c W95 FAT32 (LBA)
hello_grisp-0.1.0-grisp2.img2       63488  350207  286720  140M 83 Linux
hello_grisp-0.1.0-grisp2.img3      350208  636927  286720  140M 83 Linux
hello_grisp-0.1.0-grisp2.img4      636928 1685503 1048576  512M 83 Linux
$ mount -o loop,offset=2097152 artefacts/hello_grisp-0.1.0-grisp2.img /tmp/sdcard1/
# Mounting partition 0 with offset 4096*512=2097152
$ sudo mount -o loop,offset=2097152 hello_grisp-0.1.0-grisp2.img /tmp/hello_grisp_disk
$ ls -la /tmp/hello_grisp_disk
total 3727
drwxr-xr-x  3 root root   16384 ene  1  1970 .
drwxrwxrwt 28 root root   12288 ene 28 16:04 ..
drwxr-xr-x  3 root root     512 ene  1  1980 loader
-rwxr-xr-x  1 root root   26173 ene  1  1980 oftree
-rwxr-xr-x  1 root root 3759656 ene  1  1980 zImage.a
$ sudo umount /tmp/hello_grisp_disk
# Mounting partition 1 with offset 63488*512=32505856
$ sudo mount -o loop,offset=32505856 hello_grisp-0.1.0-grisp2.img /tmp/hello_grisp_disk
$ ls -la /tmp/hello_grisp_disk
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
drwxr-xr-x  2 root   root       3 sep  1 22:26 proc
drwx------  2 root   root       3 sep  1 22:26 root
drwxr-xr-x  2 root   root       3 sep  1 22:26 run
drwxr-xr-x  2 root   root     306 sep  1 22:26 sbin
drwxrwxr-x  3 root   root      29 ene 27 19:48 srv
drwxr-xr-x  2 root   root       3 sep  1 22:26 sys
drwxrwxrwt  2 root   root       3 sep  1 22:26 tmp
drwxr-xr-x  6 root   root      75 sep  1 22:26 usr
drwxr-xr-x  9 root   root      97 sep  1 22:26 var
$ sudo umount /tmp/hello_grisp_disk
```


### Troubleshooting

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
