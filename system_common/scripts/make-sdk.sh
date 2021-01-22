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
#
# Outputs:
#   Archive tarball
#

set -e

if [[ -z "$GRISP_TARGET_NAME" ]]; then
    echo "ERROR: environment variable GRISP_TARGET_NAME must be defined"
    exit 1
fi


source "$( dirname "$0" )/../../scripts/common.sh" "$GRISP_TARGET_NAME"

BUILD_DIR="${GLB_SYSTEM_BUILD_DIR}/build"

if [[ ! -x "${GLB_SDK_HOST_DIR}/bin/erlc" ]]; then
	echo "ERROR: erlang wasn't build for the host"
	exit 1
fi

if [[ ! -x "${GLB_SDK_HOST_DIR}/bin/rebar3" ]]; then
	echo "ERROR: rebar3 wasn't build for the host"
	exit 1
fi

if [[ ! -x "${GLB_SDK_HOST_DIR}/bin/mksquashfs" ]]; then
	echo "ERROR: squashfs wasn't build for the host"
	exit 1
fi

cat > "${GLB_SDK_DIR}/VERSIONS" << EOT
# Grisp system image
GRISP_COMMON_SYSTEM_VER="${GLB_COMMON_SYSTEM_VER}"
GRISP_TARGET_NAME="$GLB_TARGET_NAME"
GRISP_TARGET_SYSTEM_VER="${GLB_TARGET_SYSTEM_VER}"
EOT

${GLB_SCRIPT_DIR}/git-info.sh -d -o "${GLB_SDK_DIR}/GIT"

# Copy the built configuration over
cp "$BUILD_DIR/defconfig" "$GLB_SDK_DIR"
cp "$BUILD_DIR/.config" "$GLB_SDK_DIR"

# Copy the images directories over
cp -R "$BUILD_DIR/images" "$GLB_SDK_DIR"
# Copy the staging link that should point to the host directory
cp -R "$BUILD_DIR/staging" "$GLB_SDK_DIR"

tar -C "${GLB_SDK_BASE_DIR}/.." -cf - "$GLB_SDK_NAME" \
    | pv -s $( du -sb "$GLB_SDK_BASE_DIR" | awk '{print $1}' ) \
    | gzip > "$GLB_ARTEFACTS_DIR/${GLB_SDK_FILENAME}"
