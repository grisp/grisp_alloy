#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../scripts/common.sh" "$GRISP_TARGET_NAME"

# Required to build FIT image
cp -rf ${GLB_TARGET_SYSTEM_DIR}/linux/kernel_without_initramfs.its.template "${BINARIES_DIR}"
cp -rf ${GLB_TARGET_SYSTEM_DIR}/linux/kernel_with_initramfs.its.template "${BINARIES_DIR}"
