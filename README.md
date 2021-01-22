# Grisp Linux Builder

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
$ ./build-toolchain.sh TARGET
```

e.g.

```sh
$ ./build-toolchain.sh grisp2
```


## Build SDK

The toolchain must have been built previously.

```sh
$ ./build-sdk.sh TARGET
```

e.g.

```sh
$ ./build-sdk.sh grisp2
```

## Build Firware Update

Both the toolchain and the SDK must have been built previously.

```sh
$ ./build-firmware.sh TARGET PATH_TO_ERLANG_PROJECT
```

e.g.

```sh
$ ./build-firmware.sh grisp2 samples/hello_grisp
```

In addition to the firmware, an image file can be generated:

```sh
$ ./build-firmware.sh -i TARGET PATH_TO_ERLANG_PROJECT
```

e.g.

```sh
$ ./build-firmware.sh -i grisp2 samples/hello_grisp
```

Keep in mind that image file could be a lot bigger than the firmware.


### Burn Firmware

```sh
$ fwup -a -d SD_CARD_DEVICE -i FIRMWARE -t complete
```

e.g.

```sh
$ fwup -a -d /dev/sdc -i hello_grisp-0.1.0-grisp2.fw -t complete
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
