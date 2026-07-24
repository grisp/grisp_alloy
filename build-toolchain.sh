#!/usr/bin/env bash

# build-toolchain.sh - GRiSP Alloy Toolchain Builder
#
# DEVELOPER OVERVIEW:
# Builds cross-compilation toolchain for embedded targets using crosstool-NG.
# The toolchain includes GCC, binutils, glibc/musl, and other essential tools
# needed to compile software for the target architecture.
#
# HIGH-LEVEL FLOW:
# 1. Parse arguments and handle Vagrant VM execution if needed
# 2. Load target-specific toolchain configuration (defconfig)
# 3. Delegate to appropriate toolchain build script (e.g., build-crosstool-ng.sh)
#
# OUTPUT:
# - Cross-compilation toolchain in GLB_TOOLCHAIN_DIR
# - Compressed toolchain archive in artefacts/

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-toolchain.sh OPTIONS TARGET"
    echo "OPTIONS:"
    echo " -h | --help"
    echo "    Show this."
    echo " -d | --debug"
    echo "    Print scripts debug information."
    echo " -c | --clean"
    echo "    Cleanup the curent state and start building from scratch."
    echo " -V | --force-vagrant"
    echo "    Using the Vagrant VM even on Linux."
    echo " -P | --provision"
    echo "    Re-provision the vagrant VM; use to reflect some changes to the VM."
    echo " -K | --keep-vagrant"
    echo "    Keep the vagrant VM running after exiting."
    echo " -b | --print-config"
    echo "    Print the resolved toolchain config and exit."
    echo " --external <DIR>"
    echo "    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs."
    echo
    echo "e.g. build-toolchain.sh grisp2"
}

# Parse script's arguments
source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 "${DEBUG:-0}"
args_add c clean ARG_CLEAN flag true false
args_add V force-vagrant ARG_FORCE_VAGRANT flag true false
args_add P provision ARG_PROVISION_VAGRANT flag true false
args_add K keep-vagrant ARG_KEEP_VAGRANT flag true false
args_add b print-config ARG_PRINT_CONFIG flag true false
args_add "" external ARG_EXTERNAL_DIRS accum

if ! args_parse "$@"; then
    exit 1
fi
if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi

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
# Toolchain builds require Linux, so non-Linux hosts use VM
if [[ $ARG_FORCE_VAGRANT = true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    NEW_ARGS=( )
    if [[ $ARG_DEBUG -gt 0 ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-d" )
    fi
    if [[ $ARG_CLEAN == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-c" )
    fi
    if [[ $ARG_PRINT_CONFIG == true ]]; then
        NEW_ARGS+=( "--print-config" )
    fi
    for external_dir in "${ARG_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
    done
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-toolchain.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE
# Load target-specific toolchain configuration
alloy_resolve_toolchain_defconfig TOOLCHAIN_DEFCONFIG "$GLB_TARGET_NAME" "$BUILD_OS" "$BUILD_ARCH"

if [[ ! -e $TOOLCHAIN_DEFCONFIG ]]; then
    error 1 "Cannot find toolchain configuration $TOOLCHAIN_DEFCONFIG"
fi

if [[ $ARG_PRINT_CONFIG == true ]]; then
    echo "Toolchain config: $TOOLCHAIN_DEFCONFIG"
    echo "Toolchain config source: ${GLB_TOOLCHAIN_CONFIG_SOURCE:-unknown}"
    echo "Target system: $GLB_TARGET_SYSTEM_DIR"
    echo "Target bundle root: ${GLB_TARGET_BUNDLE_ROOT:-}"
    exit 0
fi

# Extract toolchain type from config (e.g., "crosstool-ng")
TOOLCHAIN=$( read_defconfig_key $TOOLCHAIN_DEFCONFIG GLB_TOOLCHAIN_TYPE )

# Find and execute appropriate toolchain build script
TOOLCHAIN_BUILD_SCRIPT="${GLB_TOOLCHAIN_SCRIPT_DIR}/build-${TOOLCHAIN}.sh"
if [[ ! -x $TOOLCHAIN_BUILD_SCRIPT ]]; then
    error 1 "Cannot find toolchain build script $TOOLCHAIN_BUILD_SCRIPT"
fi

# Execute toolchain-specific build script with configuration
CLEAN=$ARG_CLEAN GLB_TOP_DIR="${GLB_TOP_DIR}" $TOOLCHAIN_BUILD_SCRIPT "$GLB_TARGET_NAME" "$TOOLCHAIN_DEFCONFIG"
