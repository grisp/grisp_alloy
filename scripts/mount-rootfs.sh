#!/usr/bin/env bash

set -e

SCRIPT_NAME="$( basename $0 )"
SCRIPT_DIR="$( cd $( dirname $0 ); pwd )"
APP_NAME="${1:-hello_grisp}"

cd "${SCRIPT_DIR}/../artefacts"

FIRMWARE_NAME="$( ls ${APP_NAME}-*.fw )"
IMAGE_NAME="${FIRMWARE_NAME/.fw/.img}"
MOUNT_DIR="/tmp/${APP_NAME}-rootfs"
SDK_BIN_DIR="$( ls -1d /opt/grisp_linux_sdk/*/grisp2/*/host/bin/ )"

mkdir -p "$MOUNT_DIR"
rm -f "$IMAGE_NAME"
touch "$IMAGE_NAME"
"${SDK_BIN_DIR}/fwup" -a -d "$IMAGE_NAME" -t complete -i "$FIRMWARE_NAME"
sudo mount -o loop,offset=32505856 "$IMAGE_NAME" "$MOUNT_DIR"
