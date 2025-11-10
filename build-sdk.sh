#!/usr/bin/env bash

# build-sdk.sh - GRiSP Alloy SDK Builder
#
# DEVELOPER OVERVIEW:
# Builds the Software Development Kit using Buildroot, which includes:
# - Base Linux root filesystem (rootfs.squashfs)
# - Cross-compiled Erlang/OTP runtime and libraries
# - System libraries and utilities
# - FWUP configuration for firmware packaging
#
# HIGH-LEVEL FLOW:
# 1. Parse arguments and handle Vagrant VM execution if needed
# 2. Prepare build environment and download Buildroot
# 3. Merge common and target-specific buildroot configurations
# 4. Execute Buildroot build process
# 5. Package SDK as compressed archive
#
# OUTPUT:
# - SDK directory with rootfs, toolchain, and configuration
# - Compressed SDK archive in artefacts/

set -e

ARGS=( "$@" )

BR_VERSION="2025.05"

show_usage()
{
    echo "USAGE: build-sdk.sh OPTIONS TARGET"
    echo "OPTIONS:"
    echo " -h | --help"
    echo "    Show this."
    echo " -d | --debug"
    echo "    Print scripts debug information."
    echo " -b | --print-buildroot"
    echo "    Print the buildroot environment variables."
    echo " -r | --rebuild"
    echo "    Try running buildroot only, if possible; may be enough if there"
    echo "    has been only very small changes made to the SDK files."
    echo " -c | --clean"
    echo "    Cleanup the current state and start building from scratch."
    echo " -V | --force-vagrant"
    echo "    Using the Vagrant VM even on Linux."
    echo " -P | --provision"
    echo "    Re-provision the vagrant VM; use to reflect some changes to the VM."
    echo " -K | --keep-vagrant"
    echo "    Keep the vagrant VM running after exiting."
    echo " -p | --clean-package <PACKAGE_PREFIX>"
    echo "    Clean given package prefix; can be used with --rebuild to rebuild a package."
    echo
    echo "e.g. build-sdk.sh grisp2"
}

# Parse script's arguments (GNU-like long/short options)
source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 0
args_add b print-buildroot ARG_BRCMD flag true false
args_add r rebuild ARG_REBUILD flag true false
args_add c clean ARG_CLEAN flag true false
args_add V force-vagrant ARG_FORCE_VAGRANT flag true false
args_add P provision ARG_PROVISION_VAGRANT flag true false
args_add K keep-vagrant ARG_KEEP_VAGRANT flag true false
args_add p clean-package ARG_CLEAN_PACKAGES accum

if ! args_parse "$@"; then
    exit 1
fi
if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi
# Positional TARGET
POSITIONALS=( "${POSITIONAL[@]}" )
if [[ ${#POSITIONALS[@]} -eq 0 ]]; then
    echo "ERROR: Missing TARGET"
    show_usage
    exit 1
fi
ARG_TARGET="${POSITIONALS[0]}"
if [[ ${#POSITIONALS[@]} -gt 1 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

# Load common variables and functions
source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"
set_debug_level "$ARG_DEBUG"

# VAGRANT VM EXECUTION BLOCK
# Buildroot requires Linux environment for proper cross-compilation
if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    NEW_ARGS=( )
    if [[ ${ARG_DEBUG_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--debug" )
    fi
    if [[ ${ARG_BRCMD_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--print-buildroot" )
    fi
    if [[ ${ARG_REBUILD_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--rebuild" )
    fi
    if [[ ${ARG_CLEAN_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--clean" )
    fi
    for p in "${ARG_CLEAN_PACKAGES[@]}"; do
        NEW_ARGS+=( "--clean-package" "$p" )
    done
    NEW_ARGS+=( "$ARG_TARGET" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-sdk.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE
# Validate host environment - buildroot needs Linux with supported architecture
if [[ $HOST_OS != "linux" ]]; then
    error 1 "${HOST_OS} is not support, only linux"
fi

if [[ $HOST_ARCH != "x86_64" && $HOST_ARCH != "aarch64" ]]; then
    error 1 "$HOST_ARCH is not supported, only x86_64 or aarch64"
fi

# BUILDROOT CONFIGURATION FILES
# Common defconfig: shared settings across all targets
# Target defconfig: target-specific overrides and additions
COMMON_SYSTEM_DEFCONFIG="${GLB_COMMON_SYSTEM_DIR}/defconfig"
TARGET_SYSTEM_DEFCONFIG="${GLB_TARGET_SYSTEM_DIR}/defconfig"

if [ ! -d "$GLB_TARGET_SYSTEM_DIR" ]; then
    error 1 "Target ${GLB_TARGET_NAME} not supported, directory not found: ${GLB_TARGET_SYSTEM_DIR}"
fi

if [ ! -f "$COMMON_SYSTEM_DEFCONFIG" ]; then
    error 1 "File not found: ${COMMON_SYSTEM_DEFCONFIG}"
fi

if [ ! -f "$TARGET_SYSTEM_DEFCONFIG" ]; then
    error 1 "File not found: ${TARGET_SYSTEM_DEFCONFIG}"
fi

# BUILDROOT BUILD DIRECTORIES
BUILDROOT_PATH="${GLB_SYSTEM_BUILD_DIR}/buildroot"
BUILD_DIR="${GLB_SYSTEM_BUILD_DIR}/build"
FINAL_DEFCONFIG="${BUILD_DIR}/defconfig"
CHECKPOINTS_DIR="${GLB_SYSTEM_BUILD_DIR}/checkpoints"

# BUILDROOT MAKE PARAMETERS
# Pass GRiSP-specific variables to buildroot for use in external packages
BUILDROOT_MAKE_PARAMS=(
    -C "$BUILDROOT_PATH" \
    O="$BUILD_DIR" \
    BR2_EXTERNAL="$GLB_COMMON_SYSTEM_DIR" \
    BR2_DEFCONFIG="$FINAL_DEFCONFIG" \
    GRISP_TOP_DIR="$GLB_TOP_DIR" \
    GRISP_COMMON_SYSTEM_DIR="$GLB_COMMON_SYSTEM_DIR" \
    GRISP_TARGET_SYSTEM_DIR="$GLB_TARGET_SYSTEM_DIR" \
    GRISP_TARGET_NAME="$GLB_TARGET_NAME" \
    GRISP_BUILD_HOST_ARCH="$HOST_ARCH" \
    GLB_DEBUG="$GLB_DEBUG"
    # BR2_INSTRUMENTATION_SCRIPTS="$GLB_COMMON_SYSTEM_DIR/scripts/debug.sh"
)

if [[ $ARG_DEBUG -gt 0 ]]; then
    BUILDROOT_MAKE_PARAMS=( ${BUILDROOT_MAKE_PARAMS[@]} "V=1" )
fi

if [[ $ARG_BRCMD == "true" ]]; then
    echo "Buildroot command:"
    echo "make ${BUILDROOT_MAKE_PARAMS[@]}"
    exit 0
fi

if [[ $ARG_CLEAN == "true" ]]; then
    rm -rf "$CHECKPOINTS_DIR"
fi

if [[ $ARG_REBUILD == "true" ]]; then
    # Removes the prepare_buildroot and run_buildroot checkpoints,
    # it should be enough for small changes, but there is no guarantee
    rm -f "${CHECKPOINTS_DIR}/prepare_buildroot"
    rm -f "${CHECKPOINTS_DIR}/run_buildroot"
fi

# Clean specific packages if requested (-p flag)
for p in ${ARG_CLEAN_PACKAGES[@]}; do
    echo rm -rf ${BUILD_DIR}/build/$p*
    rm -rf ${BUILD_DIR}/build/$p*
done

# BUILD STEP FUNCTIONS
# These functions are executed using the checkpoint system to allow resuming builds

prepare_environment()
{
    echo "Preparing environment..."
    rm -rf "$GLB_SYSTEM_BUILD_DIR"
    rm -rf "$GLB_SDK_BASE_DIR"/*
    mkdir -p "$GLB_ARTEFACTS_DIR"
    mkdir -p "$GLB_SYSTEM_BUILD_DIR"
    mkdir -p "$GLB_SYSTEM_CACHE_DIR"
    mkdir -p "$CHECKPOINTS_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$GLB_SDK_BASE_DIR"
    chgrp $USER "$GLB_SDK_BASE_DIR"
    chmod 775 "$GLB_SDK_BASE_DIR"
}

checkout_source_code()
{
    # Download and extract Buildroot source code
    local extracted_dir="${GLB_SYSTEM_BUILD_DIR}/buildroot-${BR_VERSION}"
    local tarball_name="buildroot-${BR_VERSION}.tar.gz"
    local tarball_path="${GLB_ARTEFACTS_DIR}/${tarball_name}"

    # Ensure git LFS files are available (some artefacts may be stored in LFS)
    git lfs checkout || (echo "Error: please install git lfs!" && exit 1)

    # Clean up in case previous extraction failed.
    rm -fr "$extracted_dir" "$BUILDROOT_PATH"

    if [[ ! -e "$tarball_path" ]]; then
        echo "Downloading buildroot ${BR_VERSION}..."

        if [[ $BR_VERSION =~ 20[0-9][0-9]\.[0-1][0-9] ]]; then
            # This is an official release and is hosted on the main
            # download site.
            local download_url="https://buildroot.org/downloads/${tarball_name}"
        else
            # This is an intermediate release and can be downloaded from
            # Buildroot's cgit instance.
            local download_url="https://git.busybox.net/buildroot/snapshot/${tarball_name}"
        fi

        cd "${GLB_ARTEFACTS_DIR}"
        wget "$download_url"
        local ret="$?"
        if [ $ret != 0 ]; then
            error $ret "Failed to download ${tarball_name} from location ${download_url}"
        fi
    else
        echo "Buildroot ${BR_VERSION} already cached."
    fi

    echo "Extracting buildroot ${BR_VERSION}..."
    # Extract the cached tarball. We can't rely on the first level
    # directory naming, so force it to the expected path
    mkdir -p "$extracted_dir"
    tar xzf "$tarball_path" -C "$extracted_dir" --strip-components=1

    # Symlink for easier access
    ln -s "$extracted_dir" "$BUILDROOT_PATH"

    echo "Applying buildroot ${BR_VERSION} patches..."
    "${BUILDROOT_PATH}/support/scripts/apply-patches.sh" "${BUILDROOT_PATH}" "$GLB_COMMON_SYSTEM_DIR/patches/buildroot"

    ln -sf "$GLB_SYSTEM_CACHE_DIR" "${BUILDROOT_PATH}/dl"
}

prepare_buildroot()
{
    # Merge common and target-specific buildroot configurations
    cat > "$FINAL_DEFCONFIG" << EOF
########## GENERATED BY BUILDING SCRIPT
BR2_HOST_DIR="${GLB_SDK_HOST_DIR}"

########## FROM COMMON SYSTEM ${GLB_COMMON_SYSTEM_VER}
$( cat "$COMMON_SYSTEM_DEFCONFIG" )

########## FROM ${GLB_TARGET_NAME} TARGET SYSTEM ${GLB_TARGET_SYSTEM_VER}
$( cat "$TARGET_SYSTEM_DEFCONFIG" )
EOF

    # Generate final buildroot .config from merged defconfig
    echo "Configuring buildroot for $GLB_TARGET_NAME..."
    make "${BUILDROOT_MAKE_PARAMS[@]}" defconfig
}

run_buildroot()
{
    # Execute main buildroot build (cross-compile all packages)
    echo "Run buildroot for $GLB_TARGET_NAME..."
    make "${BUILDROOT_MAKE_PARAMS[@]}"
}

make_sdk()
{
    # Package SDK as compressed archive for distribution
    echo "Creating SDK package..."
    make "${BUILDROOT_MAKE_PARAMS[@]}" grisp-sdk
}

# CHECKPOINT EXECUTION
# Execute build steps with checkpoint system for resumable builds
# Each step is skipped if its checkpoint file exists (unless -c or -r used)
checkpoint prepare_environment "$CHECKPOINTS_DIR"
checkpoint checkout_source_code "$CHECKPOINTS_DIR"
checkpoint prepare_buildroot "$CHECKPOINTS_DIR"
checkpoint run_buildroot "$CHECKPOINTS_DIR"
make_sdk

echo "Done"
