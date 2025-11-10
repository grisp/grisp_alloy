# Kontron AL/BL iMX8M Mini System

## Firmware layout and storage mapping

The firmware layout is defined in [`fwup.conf`](fwup.conf) and mirrored in
[`crucible.sh`](crucible.sh) (the `GSU_PARTITIONS` variable).
Keep these two in sync.

- Definition: `fwup.conf` declares the GPT table, the bootloader offsets and the dual U-Boot environments.
- Packaging: `crucible.sh` uses the same layout when generating the software update package.

Partition scheme (GPT):

- p0 reserved, 128 MiB: raw area before the first partition
- p1 boot, FAT32, 64 MiB: contains `fitImage_A` and `fitImage_B`
- p2 rootfs A, squashfs, 256 MiB
- p3 rootfs B, squashfs, 256 MiB
- p4 data, f2fs, all remaining space

Bootloader and environment:

- U-Boot is written at 33 KiB offset in the user area
  (`UBOOT_OFFSET = 66` 512-byte blocks). The `complete` task in `fwup.conf`
  writes it to the media.
- Two redundant U-Boot environments are placed immediately after the bootloader
  area; their offsets are computed as `UBOOT_ENV_PRIMARY_OFFSET` and
  `UBOOT_ENV_SECONDARY_OFFSET` in `fwup.conf`.
- Today, when booting from eMMC, the ROM still loads the bootloader from the
  SPI NOR flash. We nevertheless write the bootloader to the eMMC user area and
  plan to boot directly from eMMC in the near future.

Mirroring in packaging scripts:

- `crucible.sh` contains `GSU_PARTITIONS` with the same GUIDs, offsets and sizes
  as in `fwup.conf`.
- Any change to sizes, offsets or partition ordering in one file must be
  reflected in the other.

U-Boot environment configuration:

- If you change the environment addresses/offsets, update [`uboot.config`](uboot/uboot.config),
  [`fw_env.config`](rootfs_overlay/etc/fw_env.config) and the
  [Kontron AL/BL iMX8M Mini updater HAL](https://github.com/grisp/grisp_updater_kalblimx8mm/blob/main/src/grisp_updater_kalblimx8mm.erl#L75)
  so the tools target the correct locations.

Data partition initialization:

- The `data` partition (p4) is not formatted during firmware setup.
  It is created/repaired on first boot by [`early-init.sh`](../system_common/board/grisp-common/rootfs_overlay/sbin/early-init.sh)
  and mounted at `/data` as f2fs.

Runtime device mapping (erlinit links):

- `erlinit` provides stable aliases that track the active boot device:
  - `/dev/rootdisk0` points to `/dev/mmcblk0` when running from eMMC, and to `/dev/mmcblk1` when running from SD card
  - `/dev/rootdisk0p1` reserved (no filesystem)
  - `/dev/rootdisk0p2` boot (FAT32) with FIT images, mounted at `/boot`
  - `/dev/rootdisk0p3` system A (squashfs), mounted at `/` when active
  - `/dev/rootdisk0p4` system B (squashfs), mounted at `/` when active
  - `/dev/rootdisk0p5` data (f2fs), mounted at `/data`

Use these aliases in scripts and tooling (`fw_env.config`, updater logic) to
remain agnostic to whether the system is currently running from eMMC or SD.


## Building

To package a firmware for the Kontron AL/BL iMX8M Mini board, you need a
toolchain, an SDK, and an application. The toolchain can be built once
and reused. If anything is changed in the common configuration or in the
target system configuration, the SDK needs to be rebuilt. Otherwise,
once the SDK is built, application changes only require building the
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

To rebuild the toolchain from scratch, and be sure all configuration changes
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
option. This will generate the additional artefacts:

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

Then you can use the `fwup` command to write the SD card:

```sh
fwup -a -d <DEVICE> -i artefacts/hello_grisp-0.1.0-kontron-albl-imx8mm.fw -t complete
```


### Get U-Boot environment variables

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

Add it to your host authorized keys with copy/paste from the console:

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
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.1-kontron-albl-imx8mm.fw -t complete")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_elixir-0.2.1-kontron-albl-imx8mm.fw /data"))
IO.puts(:os.cmd(~c"fwup --unsafe -a -d /dev/null -i /data/hello_elixir-0.2.1-kontron-albl-imx8mm.fw -t bootloader"))
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.1-kontron-albl-imx8mm.fw -t complete"))
```


### Manual A/B Software Upgrade with fwup

If SSH is used to pull the firmware on the device, ensure the SSH client is setup,
and an IP has been allocated. You can also setup an SSH server in your application
and scp the file to the device, or use the sdcard to get the firware file.
You can use the `/data` directory that is writable to store the firmware.

To pull the firmware using SSH client from Erlang console:

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_grisp-0.2.2-kontron-albl-imx8mm.fw /data")]).
```

or from Elixir console:

```elixir
IO.puts(:os.cmd(~c"scp -i /data/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null <USERNAME>@D<EV_HOST_IP>:<PATH_TO_GRISP_ALLOY>/artefacts/hello_elixir-0.2.2-kontron-albl-imx8mm.fw /data"))
```

Then, apply the upgrade.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.2-kontron-albl-imx8mm.fw -t upgrade")]).
```

or the Elixir console:

```elixir
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

At any moment the special `status` task can be run to get information about the
A/B software update status.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.2-kontron-albl-imx8mm.fw -t status")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.2-kontron-albl-imx8mm.fw -t status"))
```

If software rollback is available because a previous firmware was validated and
no further upgrade attempts were made, it is possible to rollback to the previous
software version.

From Erlang console:

```erlang
io:format("~s~n", [os:cmd("fwup -a -d /dev/mmcblk0 -i /data/hello_grisp-0.2.2-kontron-albl-imx8mm.fw -t rollback")]).
```

From Elixir console:

```elixir
IO.puts(:os.cmd(~c"fwup -a -d /dev/mmcblk0 -i /data/hello_elixir-0.2.2-kontron-albl-imx8mm.fw -t rollback"))
```

### Manual A/B Software Upgrade with grisp_updater

For this to work, your application needs to include [grisp_updater_kalblimx8mm](https://github.com/grisp/grisp_updater_kalblimx8mm).
To generate the software update package used by grisp_updater, you need to pass the option `-u` to `build-firmware.sh`


#### Using Tarball

Copy the software update package, by setting up an IP address using DHCP, then
either pulling it from the device or pushing it using scp. Then you can update
using grisp_updater.

From Erlang console:

```erlang
grisp_updater:update(<<"tarball:///data/hello_grisp-0.1.0-kontron-albl-imx8mm.tar">>).
```

From Elixir console:

```elixir
:grisp_updater.update("tarball:///data/hello_grisp-0.1.0-kontron-albl-imx8mm.tar").
```

### Using HTTP

Run the artefact server in grisp_alloy:

```shell
./artefact_server
```

**WARNING**: Running the artefact server without HTTPS will give open read
access to all the files under the artefacts directory to your local network.


On the device, set up the IP address to be able to access your host machine
using DHCP, then you can update using HTTP.

From Erlang console:

```erlang
grisp_updater:update(<<"http://<HOST_IP>:8080/hello_grisp-0.1.0-kontron-albl-imx8mm">>).
```

From Elixir console:

```elixir
:grisp_updater.update("http://<HOST_IP>:8080/hello_grisp-0.1.0-kontron-albl-imx8mm").
```

### Using HTTPS

For HTTPS software update with signature verification to work, the firmware
must have been built with a security pack, so the firware contains all the
required security material.

In addition, when using a develpment server with self-signed certificate,
you need to ensure the certificate hostname resolve to your development machine.
For that you may have to add a custom overlay using `./build-firmware.sh` option
`-o` that will ad a `/etc/hosts` file resolving the certificate hostname to
your development machine IP.

Run the artefact server in grisp_alloy:

```shell
./artefact_server -S /path/to/security_pack
```

On the device, set up the IP address to be able to access your host machine
using DHCP, then you can update using HTTP.

From Erlang console:

```erlang
grisp_updater:update(<<"https://<HOSTNAME>:8443/hello_grisp-0.1.0-kontron-albl-imx8mm">>).
```

From Elixir console:

```elixir
:grisp_updater.update("https://<HOSTNAME>:8443/hello_grisp-0.1.0-kontron-albl-imx8mm").
```

### Validating

After updating either from tarball or HTTP, you need to reboot the device and
mark the system as validated.

From Erlang console:

```erlang
grisp_updater:validate().
```

From Elixir console:

```elixir
:grisp_updater.validate().
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
