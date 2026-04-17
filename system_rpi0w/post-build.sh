#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../scripts/common.sh" "$GRISP_TARGET_NAME"

# Stage target fwup includes so that system_rpi0w/fwup.conf's
#   include("${GRISP_SYSTEM}/images/fwup_include/fwup-common.conf")
# resolves at firmware build time. Mirrors system_grisp2/post-build.sh:13.
cp -rf "${GLB_TARGET_SYSTEM_DIR}/fwup_include" "${BINARIES_DIR}"

# Stage the per-slot boot text files that fwup.conf's file-resources point
# at directly via ${GRISP_SYSTEM}/images/<name>. Unlike zImage / DTBs /
# rpi-firmware blobs these don't come from Buildroot, so post-build has to
# drop them in $BINARIES_DIR itself.
cp -f "${GLB_TARGET_SYSTEM_DIR}/config.txt"     "${BINARIES_DIR}/"
cp -f "${GLB_TARGET_SYSTEM_DIR}/cmdline-a.txt"  "${BINARIES_DIR}/"
cp -f "${GLB_TARGET_SYSTEM_DIR}/cmdline-b.txt"  "${BINARIES_DIR}/"
cp -f "${GLB_TARGET_SYSTEM_DIR}/autoboot-a.txt" "${BINARIES_DIR}/"
cp -f "${GLB_TARGET_SYSTEM_DIR}/autoboot-b.txt" "${BINARIES_DIR}/"

# Ensure /boot exists in the squashfs as an empty mount point; erlinit
# later mounts /dev/mmcblk0p2 (BOOT-A) here read-only (see erlinit.config).
mkdir -p "${TARGET_DIR}/boot"

# Phase 7: generate ops.fw here for runtime partition maintenance.
# mkdir -p "${TARGET_DIR}/usr/share/fwup"
# ${HOST_DIR}/usr/bin/fwup -c -f "${GLB_TARGET_SYSTEM_DIR}/fwup-ops.conf" \
#     -o "${TARGET_DIR}/usr/share/fwup/ops.fw"
