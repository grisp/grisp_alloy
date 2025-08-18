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

```erlang
io:format("~s~n", [os:cmd("fw_printenv -l /tmp")]).
```


### Get Device IP Address

From Erlang console:

```erlang
f(IP), {ok, [{addr, IP}]} = inet:ifget("eth0", [addr]), io:format("IP Address: ~w.~w.~w.~w~n", [element(1, IP), element(2, IP), element(3, IP), element(4, IP)]), IP.
```

To get an IP you may need to start udhcpc (it can take some time).

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("udhcpc -i eth0 -p /tmp/udhcpc.pid")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"udhcpc -i eth0 -p /tmp/udhcpc.pid"))
```


### Setup SSH Client

On the device, generate an SSH key pair.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("mkdir -p /data/.ssh")]).
io:format("~s~n", [os:cmd("ssh-keygen -t ed25519 -N '' -f /data/.ssh/id_ed25519")]).
io:format("~s~n", [element(2, file:read_file("/data/.ssh/id_ed25519.pub"))]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"mkdir -p /data/.ssh"))
IO.puts(:os.cmd(~c"ssh-keygen -t ed25519 -N '' -f /data/.ssh/id_ed25519"))
IO.puts(elem(File.read("/data/.ssh/id_ed25519.pub"), 1))

```

Add it to your host authorized keys with copy/past from the console:

```sh
echo "ssh-ed25519 ..." > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```


### Flash a Firmware Manually

The system can be reset, either from an SD card console or from the eMMC console.
First ensure the SSH client is setup, and an IP has been allocated.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_grisp-0.2.1-kontron-albl-imx8mm.fw /data")]).
io:format("~s~n", [os:cmd("fwup --unsafe -a -d /dev/null -i /data/hello_grisp-0.2.1-kontron-albl-imx8mm.fw -t bootloader")]).
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.1-kontron-albl-imx8mm.fw -t emmc")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_elixir-0.2.1-kontron-albl-imx8mm.fw /data"))
IO.puts(:os.cmd(~c"fwup --unsafe -a -d /dev/null -i /data/hello_elixir-0.2.1-kontron-albl-imx8mm.fw -t bootloader"))
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.1-kontron-albl-imx8mm.fw -t emmc"))
```


### Manual A/B Software Upgrade

First ensure the SSH client is setup, and an IP has been allocated.
Then, apply the upgrade.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_grisp-0.2.2-kontron-albl-imx8mm.fw /data")]).
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.2-kontron-albl-imx8mm.fw -t upgrade")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_elixir-0.2.2-kontron-albl-imx8mm.fw /data"))
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.2-kontron-albl-imx8mm.fw -t upgrade"))
```

After rebooting to the new software version, you MUST validate it, otherwise,
it will revert to the previous version after 3 unvalidated boots.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.2-kontron-albl-imx8mm.fw -t validate")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.2-kontron-albl-imx8mm.fw -t validate"))
```


### Test the CAN Bus

From Elixir console:

```elixir
System.cmd("ip", ["link", "set", "can0", "up", "type", "can", "bitrate", "500000", "loopback", "on"], stderr_to_stdout: true, into: IO.stream(:stdio, :line))
System.cmd("ip", ["-details", "link", "show", "can0"], stderr_to_stdout: true, into: IO.stream(:stdio, :line))
task = Task.async(fn ->
  System.cmd("candump", ["-n", "1", "can0"], stderr_to_stdout: true, into: IO.stream(:stdio, :line))
end)
System.cmd("cansend", ["can0", "123#DEADBEEF"])
Task.await(task, 5_000)
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
