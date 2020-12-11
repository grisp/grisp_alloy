#!/usr/bin/env bash

# Usage: build-toolchain.sh [-d] TARGET
# e.g.   build-toolchain.sh grisp2

set -e

source "$( dirname "$0" )/scripts/common.sh"

show_usage()
{
    echo "USAGE: build-toolchain.sh [-d] TARGET"
    echo "  e.g. build-toolchain.sh grisp2"
}

# Parse script's arguments
OPTIND=1
TARGET=""
DEBUG="${DEBUG:-0}"
CLEAN=0
while getopts "hdc" opt; do
    case "$opt" in
    h)
        show_usage
        exit 0
        ;;
    d)
        DEBUG=1
        ;;
    c)
        CLEAN=1
        ;;
    esac
done
shift $((OPTIND-1))
[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
    echo "ERROR: Missing arguments"
    show_usage
    exit 1
fi
TARGET="$1"
shift
if [[ $# > 0 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

set_debug_level $DEBUG

TOOLCHAIN_DEFCONFIG="$GLB_TOOLCHAIN_DIR/configs/${TARGET}_${BUILD_OS}_${BUILD_ARCH}_defconfig"

if [[ ! -e $TOOLCHAIN_DEFCONFIG ]]; then
    error 1 "Cannot find toolchain configuration $TOOLCHAIN_DEFCONFIG"
fi

TOOLCHAIN=$( read_defconfig_key $TOOLCHAIN_DEFCONFIG GLB_TOOLCHAIN_TYPE )

TOOLCHAIN_BUILD_SCRIPT="${GLB_TOOLCHAIN_SCRIPT_DIR}/build-${TOOLCHAIN}.sh"
if [[ ! -x $TOOLCHAIN_BUILD_SCRIPT ]]; then
    error 1 "Cannot find toolchain build script $TOOLCHAIN_BUILD_SCRIPT"
fi

CLEAN=$CLEAN GLB_TOP_DIR="${GLB_TOP_DIR}" $TOOLCHAIN_BUILD_SCRIPT "$TOOLCHAIN_DEFCONFIG"
