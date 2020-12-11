#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../../../scripts/common.sh"

GRISP_COMMON_SYSTEM_VERSION=$(cat $GRISP_COMMON_SYSTEM_DIR/VERSION)
GRISP_TARGET_SYSTEM_VERSION=$(cat $GRISP_TARGET_SYSTEM_DIR/VERSION)

# Approximate an os-release
OS_RELEASE_FILE="${TARGET_DIR}/usr/lib/os-release"
cat << EOF > "$OS_RELEASE_FILE"
NAME=Grisp
ID=grisp
GRISP_TARGET_NAME=$GRISP_TARGET_NAME
GRISP_COMMON_SYSTEM_VERSION=$GRISP_COMMON_SYSTEM_VERSION
GRISP_TARGET_SYSTEM_VERSION=$GRISP_TARGET_SYSTEM_VERSION
GRISP_BUILDROOT_VERSION=$BR2_VERSION
EOF

# If relevent, store some extra information from git
${GLB_SCRIPT_DIR}/git-info.sh "${TARGET_DIR}/usr/lib/git-system-info"

"$GRISP_COMMON_SYSTEM_DIR/scripts/scrub-target.sh" "$1"
