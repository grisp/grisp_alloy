# Kontron AL iMX8M Mini System

## Building

To package a firmware for the Kontron LA/BL iMX8M Mini board, you need a
toolchain a SDK, and an application. The toolchain can be built a single time
and it will be reused. If anything is changed in the common configuration or
in the target system configuration, the SDK need to be rebuilt, otherwise,
once the SDK is built, changes in the application only requires building the
firmware.


### Preparing the Vagrant VM

This is an optional step, it will be done automatically if not done explicitly.
Setting up the VM explicitly and passing the `-K` option to the build scripts
will prevent the VM to be shutdown when the scripts are done.

```sh
vagrant up
```

If later on any changes are made to the configuration beside the deployed application you
will need to either pass the `-P` option to the scripts, or provision explicitly:

```sh
vagrant provision
```


### Build the toolchain

```sh
./build-toolchain.sh -K kontron-albl-imx8mm
```

To rebuild the toolchain frome scratch, and be sure all configuration changes
are taken into account:

```sh
./build-toolchain.sh -KPc kontron-albl-imx8mm
```

The toolchain artefact will be saved as:

```sh
artefacts/grisp_toolchain_aarch64_unknown_linux_gnu-1.1.linux-x86_64.tar.xz
```


### Build the SDK

```sh
./build-sdk.sh -K kontron-albl-imx8mm
```

To rebuild the SDK from scratch, and be sure all the configuration changes are
taken into account:

```sh
./build-sdk.sh -KPc kontron-albl-imx8mm
```

If **you know what you are doing** and only want to create a new SDK with changes
in exported configuration used for the firmware, but without rebuilding any
buildroot packages:

```sh
./build-sdk.sh -KPr kontron-albl-imx8mm
```

If **you know what you are doing** and only want to rebuild specific buildroot
packages:

```sh
./build-sdk.sh -KPr -p linux -p uboot kontron-albl-imx8mm
```

The SDK artefact will be saved as:

```sh
artefacts/grisp_alloy_sdk-0.2.0-kontron-albl-imx8mm-0.1.0-linux-x86_64.tar.gz
```


### Build the Firmware

To build a firmware, you must pass the directory of an erlang application:

```sh
./build-firmware.sh -K kontron-albl-imx8mm samples/hello_grisp
```

The firmware artefact will be saved as:

```sh
artefact/hello_grisp-0.1.0-kontron-albl-imx8mm.fw
```

To generate disk images in addition to the fwup firmware you can pass the `-i`
option. This will generate the aditiona artefacts:

```sh
artefacts/hello_grisp-0.1.0-kontron-albl-imx8mm.emmc.img
artefacts/hello_grisp-0.1.0-kontron-albl-imx8mm.sdcard.img
```


### Burn the Firmware to SD card

To burn the firmware to SD card, insert the sd card and figure out the device for
it:

```sh
diskutil list # On MacOS
```

Then you can use the `fwup command to write the SD card:

```sh
fwup -a -d <DEVICE> -i artefacts/hello_grisp-0.1.0-kontron-albl-imx8mm.fw -t sdcard
```

### Get uboot environment variable

From Erlang console:

```sh
io:format("~s~n", [os:cmd("fw_printenv -l /tmp")]).
```


## Random Information

### Testing Real-Time

```sh
# Basic RT latency test on isolated CPU 3
cyclictest -t1 -a3 -p 80 -n -i 1000 -l 100000

# Multi-threaded test (all CPUs)
cyclictest -t4 -p 80 -n -i 1000 -l 10000

# High-resolution test with histogram
cyclictest -t1 -a3 -p 99 -n -i 100 -l 1000000 -h 100 -q

# Explanation:
# -t1     = 1 thread
# -a3     = affinity to CPU 3 (isolated RT CPU)
# -p 80   = RT priority 80 (SCHED_FIFO)
# -n      = use nanosleep() for timing
# -i 1000 = 1000µs interval (1ms)
# -l      = number of loops
# -h 100  = histogram with 100µs buckets
# -q      = quiet mode
```


### Running Linux Menuconfig

```sh
cd linux
cp /vagrant/system_kontron-albl-imx8mm/linux/linux-v6.12-ktn.defconfig defconfig.ref
cp defconfig.ref .config
PATH=/opt/grisp_alloy_sdk/0.2.0/kontron-albl-imx8mm/0.1.0/host/bin:$PATH ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make olddefconfig
PATH=/opt/grisp_alloy_sdk/0.2.0/kontron-albl-imx8mm/0.1.0/host/bin:$PATH ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make menuconfig
PATH=/opt/grisp_alloy_sdk/0.2.0/kontron-albl-imx8mm/0.1.0/host/bin:$PATH ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make savedefconfig
grep -v '^#' defconfig.ref | grep -v '^$' | sort > defconfig.ref.clean
grep -v '^#' defconfig | grep -v '^$' | sort > defconfig.new.clean
diff -u defconfig.ref.clean defconfig.new.clean
```

Check individual configuration key status:

```sh
cd linux
./scripts/config --state CONFIG_BLK_DEV_INITRD
```


## Troubleshooting
