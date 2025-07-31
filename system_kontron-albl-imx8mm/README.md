# Kontron AL iMX8M Mini System

## Testing Real-Time

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

## Running Linux Menuconfig

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
