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

set -eo pipefail

if [[ -z "$GRISP_TARGET_NAME" ]]; then
    echo "ERROR: environment variable GRISP_TARGET_NAME must be defined"
    exit 1
fi


source "$( dirname "$0" )/../../scripts/common.sh" "$GRISP_TARGET_NAME"

BUILD_DIR="${GLB_SYSTEM_BUILD_DIR}/build"
ALLOY_STRICT_EXTERNAL_BUNDLE=false
CRUCIBLE_FILE="${GLB_TARGET_SYSTEM_DIR}/crucible.sh"
if [[ -f "$CRUCIBLE_FILE" ]]; then
    source "$CRUCIBLE_FILE"
fi
alloy_resolve_toolchain_defconfig SDK_TOOLCHAIN_DEFCONFIG "$GLB_TARGET_NAME" "$BUILD_OS" "$BUILD_ARCH"

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
rm -f "$GLB_SDK_DIR/ALLOY-RESOLVER-CONTEXT"

# Copy the built configuration over
cp "$BUILD_DIR/defconfig" "$GLB_SDK_DIR"
cp "$BUILD_DIR/.config" "$GLB_SDK_DIR"

# Copy the images directories over
rm -rf "$GLB_SDK_DIR/images"
cp -a "$BUILD_DIR/images" "$GLB_SDK_DIR"
# Copy the staging link that should point to the host directory
rm -f "$GLB_SDK_DIR/staging"
cp -a "$BUILD_DIR/staging" "$GLB_SDK_DIR"

sdk_write_manifest

# Put metadata first so capability discovery does not decompress the toolchain.
# Archive only this variant, retaining install_sdk's single leading component.
SDK_ARCHIVE_ROOT="${GLB_SDK_DIR#"$GLB_SDK_PARENT_DIR/"}"
SDK_ARCHIVE_CONTENTS=( "$SDK_ARCHIVE_ROOT/ALLOY-SDK" )
for item in "$GLB_SDK_DIR"/* "$GLB_SDK_DIR"/.[!.]* "$GLB_SDK_DIR"/..?*; do
    [[ -e "$item" || -L "$item" ]] || continue
    case "${item##*/}" in
        ALLOY-SDK|ALLOY-RESOLVER-CONTEXT) continue ;;
    esac
    SDK_ARCHIVE_CONTENTS+=( "$SDK_ARCHIVE_ROOT/${item##*/}" )
done
tar -C "$GLB_SDK_PARENT_DIR" -cf - "${SDK_ARCHIVE_CONTENTS[@]}" \
    | pv -s "$(du -sb "$GLB_SDK_DIR" | awk '{print $1}')" \
    | gzip > "$GLB_ARTEFACTS_DIR/$GLB_SDK_FILENAME"
