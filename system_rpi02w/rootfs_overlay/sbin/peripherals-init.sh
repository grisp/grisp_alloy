#!/bin/sh
# Bring up rpi02w-specific peripherals before erlinit starts the BEAM.
#
# Invoked by erlinit as a --pre-run-exec (see rootfs_overlay/etc/erlinit.config).
# Failures are logged but never fatal: the BEAM must always come up, so
# missing firmware or an unresponsive BT controller should degrade, not brick.

set -u

log() { echo "[peripherals-init] $*"; }

# -------- kernel modules ---------------------------------------------------
# Both brcmfmac (Wi-Fi, SDIO) and hci_uart (Bluetooth, UART) are =m in the
# kernel config. In theory:
#   - brcmfmac autoloads via the kernel's usermode helper when the SDIO
#     subsystem enumerates the BCM43430 modalias at ~1.9s into boot.
#   - hci_uart autoloads via the serdev binding for the `miniuart-bt` DT
#     overlay, and indeed does so at ~2.4s (we see it in dmesg before this
#     script runs).
#
# In practice brcmfmac loses the autoload race on RPi Zero 2 W: the SDIO
# coldplug uevent fires before /sbin/modprobe has modules.dep paged in,
# the single kernel request_module() call fails silently, and we end up
# at the prompt with no wlan0. Explicit modprobe here makes it
# deterministic. Bluetooth's hci_uart we re-modprobe defensively (no-op
# if serdev already loaded it). Non-fatal in both cases: the BEAM must
# come up regardless, and missing Wi-Fi/BT should degrade the system,
# not brick it.
if ! modprobe brcmfmac 2>/dev/null; then
    log "modprobe brcmfmac failed (module missing or depmod incomplete)"
fi
if ! modprobe hci_uart 2>/dev/null; then
    log "modprobe hci_uart failed (module missing or depmod incomplete)"
fi

# -------- pstore / ramoops --------------------------------------------------
# The ramoops overlay (config.txt: `dtoverlay=ramoops`) reserves a small
# RAM region whose contents survive a soft reboot. Mounting pstore here
# exposes each previous boot's kernel log as /sys/fs/pstore/dmesg-ramoops-*.
# No-op (mount fails harmlessly) if the overlay isn't active or if
# CONFIG_PSTORE_RAM is missing.
if [ -d /sys/fs/pstore ]; then
    if ! mount -t pstore pstore /sys/fs/pstore 2>/dev/null; then
        log "pstore mount failed (ramoops overlay not applied?); continuing"
    fi
fi

# -------- Bluetooth: attach BCM43438 over mini-UART ------------------------
# config.txt carries `dtoverlay=miniuart-bt`, which routes the onboard BT
# controller to ttyAMA1 at 3 Mbps. `btattach` from bluez5-utils hands the
# line discipline to the kernel's hciuart driver (CONFIG_BT_HCIUART_BCM=y
# in linux/linux-6.12.defconfig). Run in the background: we don't want the
# BEAM waiting on the BT handshake. `hciconfig hci0 up` is left to
# userspace / grisp OTP.
#
# The firmware blob (BCM43430A1.hcd) is supplied by the brcmfmac_sdio-firmware-rpi
# package (_BT sub-option); without it, btattach will attach the UART but
# leave the controller un-initialised.
if [ -c /dev/ttyAMA1 ] && command -v btattach >/dev/null 2>&1; then
    log "attaching Bluetooth on /dev/ttyAMA1 (bcm, 3 Mbps)"
    btattach -B /dev/ttyAMA1 -P bcm -S 3000000 >/dev/null 2>&1 &
fi

exit 0
