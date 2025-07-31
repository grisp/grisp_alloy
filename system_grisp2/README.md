# GRiSP 2 System

## Troubleshooting

### Boot With Debug

Fallback to barebox console during boot by pressing any key when seeing:

```
Hit m for menu or any to stop autoboot:    X
```

Then change the boot arguments and boot manually:

```sh
global linux.bootargs.extra="loglevel=8 ignore_loglevel initcall_debug panic=-1 -v --run-on-exit /bin/sh --hang-on-exit"
boot
```

If erlinit fails to start Erlang and fallback to shell, you can try:

```sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin ROOTDIR=/srv/erlang BINDIR=/srv/erlang/erts-16.0.1/bin EMU=beam PROGNAME=erlexec RELEASE_SYS_CONFIG=/srv/erlang/releases/0.0.1/sys RELEASE_ROOT=/srv/erlang RELEASE_TMP=/tmp LANG=en_US.UTF-8 LANGUAGE=en ERL_INETRC=/etc/erl_inetrc ERL_CRASH_DUMP=/tmp/erl_crash.dump /usr/bin/nbtty /srv/erlang/erts-16.0.1/bin/erlexec -config /srv/erlang/releases/0.0.1/sys.config -boot /srv/erlang/releases/0.0.1/no_dot_erlang -args_file /srv/erlang/releases/0.0.1/vm.args -boot_var RELEASE_LIB /srv/erlang/lib
```

### Get a CORE on the Device

When dropping to the shell on the device, you can get and store a core with:

```sh
dmesg -n 8
echo 0 > /proc/sys/kernel/printk_ratelimit
ulimit -c unlimited
echo '/tmp/core.%e.%p' > /proc/sys/kernel/core_pattern

# Run the command that would dump a core

mount -o remount,rw /mnt/boot
cp /tmp/core.* /mnt/boot
umount /mnt/boot
```

### Use SCP to copy a CORE

```sh
udhcpc -i eth0 -p /tmp/udhcpc.pid
scp  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/core.*  USERNAME@DEV_HOST_IP:/tmp
```

### Debug a CORE in the Vagrant VM

```sh
CORE=/home/vagrant/artefacts/core.beam.smp
EXE=/home/vagrant/_build/firmware/projects/hello_grisp/_build/default/rel/hello_grisp/erts-16.0.1/bin/beam.smp
GDB=/opt/grisp_alloy_sdk/0.2.0/grisp2/0.2.0/host/bin/armv7-unknown-linux-gnueabihf-gdb
$GDB $EXE $CORE
(gdb) set sysroot /opt/grisp_alloy_sdk/0.2.0/grisp2/0.2.0/host/arm-buildroot-linux-gnueabihf/sysroot
(gdb) set solib-absolute-prefix /opt/grisp_alloy_sdk/0.2.0/grisp2/0.2.0/host/arm-buildroot-linux-gnueabihf/sysroot
(gdb) info sharedlibrary
(gdb) info registers
(gdb) x/i $pc
(gdb) x/6i $pc-12
```
