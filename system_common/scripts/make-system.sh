#!/usr/bin/env bash

#
# This script creates a tarball with everything needed to build
# an application image on another system. It is useful to allow
# the parts that require Linux to be built separately from the
# parts that can be built on any system.
# It is intended to be called from Buildroot's Makefiles so that
# the environment is set up properly.
#
# Required envirnoment variables:
#   GRISP_TARGET_NAME = the target name
#   GRISP_COMMON_SYSTEM_DIR = the directory of the common system
#   GRISP_TARGET_SYSTEM_DIR = the directory of the target system
#
# Outputs:
#   Archive tarball
#

set -e

source "$( dirname "$0" )/../../scripts/common.sh"

TARGET_NAME="$1"
ARCHIVE_NAME="$2"

if [[ -z "$GRISP_TARGET_NAME" ]]; then
    echo "ERROR: environment variable GRISP_TARGET_NAME must be defined"
    exit 1
fi

if [[ -z "$GRISP_COMMON_SYSTEM_DIR" ]]; then
    echo "ERROR: environment variable GRISP_COMMON_SYSTEM_DIR must be defined"
    exit 1
fi

if [[ -z "$GRISP_TARGET_SYSTEM_DIR" ]]; then
    echo "ERROR: environment variable GRISP_TARGET_SYSTEM_DIR must be defined"
    exit 1
fi

BUILD_DIR="${GLB_SYSTEM_BUILD_DIR}/build"
COMMON_SYSTEM_VER="$( cat ${GRISP_COMMON_SYSTEM_DIR}/VERSION )"
TARGET_SYSTEM_VER="$( cat ${GRISP_TARGET_SYSTEM_DIR}/VERSION )"
ARCHIVE_FILE_NAME="${GLB_SDK_NAME}_${COMMON_SYSTEM_VER}_${GRISP_TARGET_NAME}_${TARGET_SYSTEM_VER}_${HOST_OS}_${HOST_ARCH}.tar.gz"
SDK_DIR="${GLB_SDK_BASE_DIR}/${COMMON_SYSTEM_VER}/${GRISP_TARGET_NAME}/${TARGET_SYSTEM_VER}"
HOST_DIR="${SDK_DIR}/host"

if [[ ! -x "${HOST_DIR}/bin/erlc" ]]; then
	echo "ERROR: erlang wasn't build for the host"
	exit 1
fi

if [[ ! -x "${HOST_DIR}/bin/rebar3" ]]; then
	echo "ERROR: rebar3 wasn't build for the host"
	exit 1
fi

if [[ ! -x "${HOST_DIR}/bin/mksquashfs" ]]; then
	echo "ERROR: squashfs wasn't build for the host"
	exit 1
fi

cat > "${SDK_DIR}/VERSIONS" << EOT
# Grisp system image
GRISP_COMMON_SYSTEM_VER="${COMMON_SYSTEM_VER}"
GRISP_TARGET_NAME="$GRISP_TARGET_NAME"
GRISP_TARGET_SYSTEM_VER="${TARGET_SYSTEM_VER}"
EOT

${GLB_SCRIPT_DIR}/git-info.sh "${SDK_DIR}/GIT"

#TODO: Copy some environment setup script

# The host files are already installed there

# Copy the built configuration over
cp "$BUILD_DIR/defconfig" "$SDK_DIR"
cp "$BUILD_DIR/.config" "$SDK_DIR"

# Copy the images directories over
cp -R "$BUILD_DIR/images" "$SDK_DIR"
# Copy the staging link that should point to the host directory
cp -R "$BUILD_DIR/staging" "$SDK_DIR"

tar -C "${GLB_SDK_BASE_DIR}/.." -cf - "$GLB_SDK_NAME" \
    | pv -s $( du -sb "$GLB_SDK_BASE_DIR" | awk '{print $1}' ) \
    | gzip > "$GLB_ARTEFACTS_DIR/${ARCHIVE_FILE_NAME}"
