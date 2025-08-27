#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../../../scripts/common.sh" "$GRISP_TARGET_NAME"

# Approximate an os-release
OS_RELEASE_FILE="${TARGET_DIR}/usr/lib/os-release"
cat << EOF > "$OS_RELEASE_FILE"
NAME=Grisp
ID=grisp
GRISP_TARGET_NAME=$GLB_TARGET_NAME
GRISP_COMMON_SYSTEM_VERSION=$GLB_COMMON_SYSTEM_VER
GRISP_TARGET_SYSTEM_VERSION=$GLB_TARGET_SYSTEM_VER
GRISP_BUILDROOT_VERSION=$BR2_VERSION
EOF

# If relevent, store some extra information from git
${GLB_SCRIPT_DIR}/git-info.sh -d -o "${TARGET_DIR}/usr/lib/git-system-info"

"$GLB_COMMON_SYSTEM_DIR/scripts/scrub-target.sh" "$1"

rm -rf "${TARGET_DIR}/var/tmp"
ln -snf "/tmp" "${TARGET_DIR}/var/tmp"
rm -rf "${TARGET_DIR}/var/run"
ln -snf "/run" "${TARGET_DIR}/var/run"
rm -rf "${TARGET_DIR}/var/lock"
ln -snf "/run/lock" "${TARGET_DIR}/var/lock"
rm -rf "${TARGET_DIR}/var/cache"
ln -snf "/run/cache" "${TARGET_DIR}/var/cache"
rm -rf "${TARGET_DIR}/var/spool"
ln -snf "/run/spool" "${TARGET_DIR}/var/spool"
rm -rf "${TARGET_DIR}/var/log"
mkdir -p "${TARGET_DIR}/var/log"
