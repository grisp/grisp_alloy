#!/bin/sh

set -efu

log() { echo "[early-init] $*"; }

# -------- settings (override with kernel cmdline: data_dev=/dev/XYZ) --------

DATA_DEV=${1:-"/dev/rootdisk0p4"}
DATA_MNT="/data"
DATA_FS="f2fs"
# Security/wear-friendly mount opts; adjust as needed.
DATA_OPTS="rw,nosuid,nodev,noexec,noatime,lazytime"

# Parse kernel cmdline override
for tok in $(cat /proc/cmdline); do
  case "$tok" in
    data_dev=*) DATA_DEV="${tok#data_dev=}" ;;
  esac
done

# Ensure runtime dirs/perms now that erlinit mounted /run and /tmp
mkdir -p /run/lock
mkdir -p /run/cache
mkdir -p /run/spool
chmod 0755 /run
chmod 0755 /run/lock
chmod 0755 /run/cache
chmod 0755 /run/spool
chmod 1777 /tmp || true
chmod 0755 /var/log

# DNS on tmpfs; bind over /etc/resolv.conf if the image doesn't ship a symlink
[ -e /run/resolv.conf ] || : > /run/resolv.conf
if [ ! -L /etc/resolv.conf ]; then
  mount --bind /run/resolv.conf /etc/resolv.conf || true
fi

# Standard RO-friendly symlinks
[ -L /var/run ]  || ln -sfn /run /var/run
[ -L /var/lock ] || ln -sfn /run/lock /var/lock
[ -L /var/cache ] || ln -sfn /run/cache /var/cache
[ -L /var/spool ] || ln -sfn /run/spool /var/spool
[ -L /var/tmp ]  || ln -sfn /tmp /var/tmp

# -------- wait for the block device --------

i=0
while [ ! -b "$DATA_DEV" ] && [ $i -lt 10 ]; do
  i=$((i+1)); sleep 1
done
if [ ! -b "$DATA_DEV" ]; then
  log "Device $DATA_DEV not found; skipping /data mount"
  exit 0
fi

# -------- try to mount; if it fails, repair or format as f2fs --------

# First, see if a quick check can make it mountable (ignore errors)
fsck.$DATA_FS -a "$DATA_DEV" >/dev/null 2>&1 || true

if ! mount -t "$DATA_FS" -o "$DATA_OPTS" "$DATA_DEV" "$DATA_MNT" >/dev/null 2>&1; then
  log "Mount failed; (re)creating $DATA_FS on $DATA_DEV (it could take some time)"
  mkfs.$DATA_FS -f -l data "$DATA_DEV"
  fsck.$DATA_FS -a "$DATA_DEV" || true
  # Try to mount again
  if ! mount -t "$DATA_FS" -o "$DATA_OPTS" "$DATA_DEV" "$DATA_MNT"; then
    log "Mount still failed after mkfs; continuing without /data"
    exit 0
  fi
fi

# Seed common dirs on first boot / general use
chown root:root /data
chmod 0755 /data
mkdir -p /data/crash
chmod 0700 /data/crash

log "/data mounted on $DATA_DEV as $DATA_FS with opts: $DATA_OPTS"
exit 0
