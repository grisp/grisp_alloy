#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../scripts/common.sh"

# TODO: Create the revert script for manually switching back to the previously
# active firmware.
#mkdir -p $TARGET_DIR/usr/share/fwup
#$HOST_DIR/usr/bin/fwup -c -f $GRISP_TARGET_SYSTEM_DIR/fwup-revert.conf -o $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $GRISP_TARGET_SYSTEM_DIR/fwup_include $BINARIES_DIR

# For now, the kernel is stored in the FAT filesystem instead of /boot .
rm -f $TARGET_DIR/boot/zImage
