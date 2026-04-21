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

# No depmod loop: with the full custom kernel defconfig there is no
# MODULE_COMPRESS_XZ, so Buildroot's own modules_install pass produces a
# working /lib/modules/<kver>/modules.dep. system_grisp2 and
# system_kontron-albl-imx8mm rely on the same Buildroot behaviour.
