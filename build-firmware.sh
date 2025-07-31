#!/usr/bin/env bash

# build-firmware.sh - GRiSP Alloy Firmware Builder
#
# DEVELOPER OVERVIEW:
# This script builds firmware images from Erlang projects for embedded GRiSP targets.
#
# HIGH-LEVEL FLOW:
# 1. Parse arguments and validate inputs
# 2. Handle Vagrant VM execution on non-Linux hosts or when forced
# 3. Install SDK if not present
# 4. Load target-specific configuration (crucible.sh) and boot scheme plugin
# 5. Build Erlang project using rebar3
# 6. Create firmware filesystem by merging SDK rootfs with project release
# 7. Package bootloader, kernel, and firmware using boot scheme
# 8. Optionally generate raw disk images
#
# KEY COMPONENTS:
# - SDK: Pre-built root filesystem and toolchain
# - Crucible: Target-specific build configuration
# - Boot scheme: Platform-specific packaging (e.g., AHAB for i.MX8)
# - FWUP: Firmware update packaging system

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-firmware.sh [-h] [-d] [-c] [-i] [-V] [-P] [-K] TARGET ERLANG_PROJECT_DIR [REBAR3_PROFILE] [SERIAL_NUMBER]"
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start from scratch"
    echo " -i Generate raw images in addition of the firmware"
    echo " -V Using the Vagrant VM even on Linux"
    echo " -P Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K Keep the vagrant VM running after exiting"
    echo
    echo "e.g. build-firmware.sh grisp2 ~/my_project"
}

# Parse script's arguments
OPTIND=1
ARG_DEBUG="${DEBUG:-0}"
ARG_CLEAN=false
ARG_GEN_IMAGES=false
ARG_FORCE_VAGRANT=false
ARG_KEEP_VAGRANT=false
while getopts "hdcistVPK" opt; do
    case "$opt" in
    d)
        ARG_DEBUG=1
        ;;
    c)
        ARG_CLEAN=true
        ;;
    i)
        ARG_GEN_IMAGES=true
        ;;
    V)
        ARG_FORCE_VAGRANT=true
        ;;
    P)
        ARG_PROVISION_VAGRANT=true
        ;;
    K)
        ARG_KEEP_VAGRANT=true
        ;;
    *)
        show_usage
        exit 0
        ;;
    esac
done
shift $((OPTIND-1))
[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
    echo "ERROR: Missing target name "
    show_usage
    exit 1
fi
ARG_TARGET="$1"
shift
if [[ $# -eq 0 ]]; then
    echo "ERROR: Missing project directory"
    show_usage
    exit 1
fi
ARG_PROJECT="$1"
shift
if [[ $# > 0 ]]; then
    ARG_PROJECT_PROFILE="$1"
    shift
else
    ARG_PROJECT_PROFILE="default"
fi
if [[ $# > 0 ]]; then
    ARG_SERIAL_DEFINED=true
    ARG_SERIAL="$1"
    shift
else
    ARG_SERIAL_DEFINED=false
    ARG_SERIAL="00000000"
fi
if [[ $# > 0 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

# Load common variables and functions (GLB_* globals, error handling, etc.)
source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"

# Validate host architecture - only modern 64-bit architectures supported
if [[ $HOST_ARCH != "x86_64" && $HOST_ARCH != "aarch64" && $HOST_ARCH != "arm64" ]]; then
    error 1 "$HOST_ARCH is not supported, only x86_64, aarch64 or arm64"
fi

if [[ ! -d $ARG_PROJECT ]]; then
    error 1 "cannot find Erlang project $ARG_PROJECT"
fi

SOURCE_PROJECT_DIR="$( cd $ARG_PROJECT; pwd )"
PROJECT_NAME="$( basename "$SOURCE_PROJECT_DIR" )"
VCS_TAG_FILE=".grisp_vcs_tag"
RSYNC_CMD=( rsync -avH --delete --exclude='.git/' --exclude='.hg/'
            --exclude='_build/' --exclude='*.beam' --exclude='*.o'
            --exclude='*.so' )

set_debug_level "$ARG_DEBUG"

# VAGRANT VM EXECUTION BLOCK
# Non-Linux hosts (macOS, etc.) or forced Vagrant mode require VM execution
# This entire block sets up VM, syncs project files, and re-executes script inside VM
if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    VAGRANT_TOP_DIR="/home/vagrant"
    VAGRANT_PROJECT_DIR="${VAGRANT_TOP_DIR}/projects/${PROJECT_NAME}"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    if [[ $ARG_CLEAN == true ]]; then
        vagrant exec rm -rf "$VAGRANT_PROJECT_DIR"
    fi
    vagrant exec mkdir -p "$VAGRANT_PROJECT_DIR"
    vagrant ssh-config > .vagrant.ssh_config

    ${RSYNC_CMD[@]} -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" \
        "$SOURCE_PROJECT_DIR"/. "vagrant@default:${VAGRANT_PROJECT_DIR}"

    if [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
        PROJECT_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$SOURCE_PROJECT_DIR" )"
        echo "$PROJECT_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${VAGRANT_PROJECT_DIR}/${VCS_TAG_FILE}"
    fi

    if [[ -d "$GLB_TOP_DIR/.git" ]]; then
        GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$GLB_TOP_DIR" )"
        echo "$GLB_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${VAGRANT_TOP_DIR}/${VCS_TAG_FILE}"
    fi

    NEW_ARGS=( )
    if [[ $ARG_DEBUG -gt 0 ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-d" )
    fi
    if [[ $ARG_CLEAN == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-c" )
    fi
    if [[ $ARG_GEN_IMAGES == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-i" )
    fi
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$VAGRANT_PROJECT_DIR" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_PROJECT_PROFILE" )

    if [[ $ARG_SERIAL_DEFINED == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_SERIAL" )
    fi

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec "${VAGRANT_TOP_DIR}/build-firmware.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE
# Clean SDK if requested (forces full rebuild)
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$GLB_SDK_BASE_DIR/*"
fi

# SDK INSTALLATION
# SDK contains pre-built root filesystem, toolchain, and base packages
# If missing, extract from cached tarball in artefacts/
if [[ ! -d $GLB_SDK_DIR ]]; then
    echo "SDK not installed, trying to install it from artefacts..."
    if [[ ! -f "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}" ]]; then
        error 1 "SDK ${GLB_SDK_FILENAME} not found in ${GLB_ARTEFACTS_DIR}"
    fi
    if [[ ! -d $GLB_SDK_BASE_DIR ]]; then
        mkdir -p "$GLB_SDK_BASE_DIR"
        chgrp "$USER" "$GLB_SDK_BASE_DIR"
        chmod 775 "$GLB_SDK_BASE_DIR"
    fi
    tar -C "$GLB_SDK_BASE_DIR" --strip-components=1 -xzf \
        "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}"
    if [[ ! -d $GLB_SDK_DIR ]]; then
        error 1 "SDK ${GLB_SDK_FILENAME} is invalid"
    fi
fi

# BUILD CONFIGURATION SETUP
# Initialize variables that will be set by crucible.sh and boot scheme plugin
BOOTSCHEME=NONE
BOOTSCHEME_KERNEL_RAMFS=false
SQUASHFS_PRIORITIES=()
FWUP_IMAGE_TARGETS=()

# CRUCIBLE: Target-specific build configuration
# Contains target-specific settings like boot scheme, kernel config, etc.
CRUCIBLE_FILE="${GLB_TARGET_SYSTEM_DIR}/crucible.sh"
if [[ ! -f "$CRUCIBLE_FILE" ]]; then
    error 1 "Crucible file for system ${GLB_TARGET_NAME} not found"
fi
source "$CRUCIBLE_FILE"

# BOOT SCHEME PLUGIN: Platform-specific packaging logic
# Each target uses different boot methods (AHAB for i.MX8, etc.)
# Plugin provides functions: bootscheme_package_bootloader, bootscheme_package_kernel, bootscheme_package_firmware
BOOTSCHEME_FILE="${GLB_SCRIPT_DIR}/plugins/bootscheme_$(echo ${BOOTSCHEME} | tr '[:upper:]' '[:lower:]').sh"
if [[ ! -f "$BOOTSCHEME_FILE" ]]; then
    error 1 "Boot scheme ${BOOTSCHEME} not found at ${BOOTSCHEME_FILE}"
fi
source "$BOOTSCHEME_FILE"

PROJECT_DIR="${GLB_FIRMWARE_BUILD_DIR}/projects/${PROJECT_NAME}"
FIRMWARE_DIR="${GLB_FIRMWARE_BUILD_DIR}/firmware"
SDK_ROOTFS="$GLB_SDK_DIR/images/rootfs.squashfs"
SDK_FWUP_CONFIG="$GLB_SDK_DIR/images/fwup.conf"
GLB_VCS_TAG="unknown"
if [[ -d "${GLB_TOP_DIR}/.git" ]]; then
    GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$GLB_TOP_DIR" )"
elif [[ -f "${GLB_TOP_DIR}/${VCS_TAG_FILE}" ]]; then
    GLB_VCS_TAG="$( cat "${GLB_TOP_DIR}/${VCS_TAG_FILE}" )"
fi

# Clean previous builds if requested
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$PROJECT_DIR"
    rm -rf "$FIRMWARE_DIR"
fi

# ERLANG PROJECT BUILD PREPARATION
# Copy source project to build directory and prepare for compilation
echo "Building project..."
mkdir -p "$PROJECT_DIR"
${RSYNC_CMD[@]} "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/${VCS_TAG_FILE}" ]] \
        && [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
    "${GLB_SCRIPT_DIR}/git-info.sh" -c "$SOURCE_PROJECT_DIR" \
        -o "$PROJECT_DIR/${VCS_TAG_FILE}"
fi
mkdir -p "$FIRMWARE_DIR"

# ERLANG PROJECT COMPILATION
# Use rebar3 to build Erlang release with cross-compiled ERTS and system libs
cd "$PROJECT_DIR"
PROJECT_VCS_TAG="unknown"
if [[ -f "$VCS_TAG_FILE" ]]; then
    PROJECT_VCS_TAG="$( cat "$VCS_TAG_FILE" )"
fi
# Set up cross-compilation environment (TARGET_ERLANG, etc.)
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"
rm -rf "_build/"
# Build release with embedded Erlang runtime for target architecture
rebar3 as "$ARG_PROJECT_PROFILE" release --system_libs "$TARGET_ERLANG" --include-erts "$TARGET_ERLANG"
cd "_build/${ARG_PROJECT_PROFILE}/rel"/*
RELEASE_DIR="$( pwd )"

APP_NAME="$( basename "$RELEASE_DIR" )"
APP_VER=""
APP_REL_DIR=$( echo "${RELEASE_DIR}/lib/${APP_NAME}-"* )
if [[ -d $APP_REL_DIR ]]; then
    BASE_FILENAME="$( basename $APP_REL_DIR )-${GLB_TARGET_NAME}"
    APP_VER="$( echo "$APP_REL_DIR" | sed "s|^.*/${APP_NAME}-\(.*\)$|\1|" )"
else
    BASE_FILENAME="${APP_NAME}-${GLB_TARGET_NAME}"
fi

FIRMWARE_FILENAME="${BASE_FILENAME}.fw"
FIRMWARE_FILE="${GLB_ARTEFACTS_DIR}/${FIRMWARE_FILENAME}"
IMAGE_BASE_FILENAME="${BASE_FILENAME}"
IMAGE_BASE_FILE="${GLB_ARTEFACTS_DIR}/${IMAGE_BASE_FILENAME}"
IMAGE_FILE_EXTENSION=".img"

# Create a priority file
SQUASHFS_PRIORITIES_FILE="$FIRMWARE_DIR/squashfs.priority"
rm -f "$SQUASHFS_PRIORITIES_FILE"
for ((i = 0; i < ${#SQUASHFS_PRIORITIES[@]}; i += 2 )); do
    echo "${SQUASHFS_PRIORITIES[i]} ${SQUASHFS_PRIORITIES[i + 1]}" >> "$SQUASHFS_PRIORITIES_FILE"
done

# FILESYSTEM OVERLAY PREPARATION
# Create overlay containing Erlang release that will be merged with SDK rootfs
echo "Updating base firmware image with project release..."

# Place Erlang release in standard location (/srv/erlang in target filesystem)
ERLANG_OVERLAY_DIR="${FIRMWARE_DIR}/rootfs_overlay/srv/erlang"
rm -rf "$ERLANG_OVERLAY_DIR"
mkdir -p "$ERLANG_OVERLAY_DIR"
cp -R "${RELEASE_DIR}/." "$ERLANG_OVERLAY_DIR"

# Remove unnecessary files from release (docs, sources, etc.) to reduce size
"${GLB_COMMON_SYSTEM_DIR}/scripts/scrub-otp-release.sh" \
    "$FIRMWARE_DIR/rootfs_overlay/srv/erlang"

# Update the os-release file
OS_RELEASE_FILE="${FIRMWARE_DIR}/rootfs_overlay/usr/lib/os-release"
mkdir -p $( dirname $OS_RELEASE_FILE )
cat << EOF > "$OS_RELEASE_FILE"
NAME="${OS_RELEASE_NAME:="${GLB_TARGET_NAME}-${PROJECT_NAME}"}"
PRETTY_NAME="${OS_RELEASE_PRETTY_NAME:="${GLB_TARGET_NAME}-${PROJECT_NAME}"}"
ID="${OS_RELEASE_ID:=${GLB_TARGET_NAME}}"
APP_NAME="${PROJECT_NAME}"
APP_VERSION="${PROJECT_VCS_TAG}"
GRISP_ALLOY_VERSION="${GLB_VCS_TAG}"
EOF

cat $OS_RELEASE_FILE

# FILESYSTEM MERGING
# Combine SDK base rootfs with project overlay into single SquashFS
"${GLB_COMMON_SYSTEM_DIR}/scripts/merge-squashfs.sh" \
    "$SDK_ROOTFS" "${FIRMWARE_DIR}/combined.squashfs" \
    "${FIRMWARE_DIR}/rootfs_overlay" "$SQUASHFS_PRIORITIES_FILE"

# BOOT SCHEME PACKAGING
# These functions are provided by the boot scheme plugin loaded earlier
# Each boot scheme handles bootloader/kernel packaging differently

# Package bootloader (U-Boot, AHAB container, etc.)
bootscheme_package_bootloader

# Package kernel (with or without initramfs)
bootscheme_package_kernel

# FIRMWARE IMAGE CREATION
# Create final .fw file using FWUP configuration and boot scheme logic
echo "Building firmware $FIRMWARE_FILENAME..."
mkdir -p "$( dirname "$FIRMWARE_FILE" )"

bootscheme_package_firmware

# OPTIONAL RAW IMAGE GENERATION (-i flag)
# Convert .fw file to raw disk images for direct writing to SD cards/eMMC
if [[ $ARG_GEN_IMAGES == true ]]; then
    FWUP="${GLB_SDK_HOST_DIR}/bin/fwup"
    # FWUP_IMAGE_TARGETS is set by boot scheme plugin (target_name, postfix pairs)
    for ((i = 0; i < ${#FWUP_IMAGE_TARGETS[@]}; i += 2 )); do
        IMAGE_TARGET="${FWUP_IMAGE_TARGETS[i]}"
        IMAGE_POSTFIX="${FWUP_IMAGE_TARGETS[i + 1]}"
        IMAGE_FILENAME="${IMAGE_BASE_FILENAME}${IMAGE_POSTFIX}${IMAGE_FILE_EXTENSION}"
        IMAGE_FILE="${IMAGE_BASE_FILE}${IMAGE_POSTFIX}${IMAGE_FILE_EXTENSION}"

        echo "Building $IMAGE_TARGET image $IMAGE_FILENAME..."
        mkdir -p "$( dirname "$IMAGE_FILE" )"

        # FWUP requires empty target file (simulates MMC device)
        rm -f "$IMAGE_FILE"
        touch "$IMAGE_FILE"

        # Convert firmware to raw image using FWUP programming mode
        "${FWUP}" -a -d "${IMAGE_FILE}" -t "${IMAGE_TARGET}" -i "$FIRMWARE_FILE"
    done
fi

echo "Done"
