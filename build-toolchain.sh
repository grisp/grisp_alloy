#!/usr/bin/env bash

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-toolchain.sh [-h] [-d] [-c] [-V] [-P] [-K] TARGET"
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start building from scratch"
    echo " -V Using the Vagrant VM even on Linux"
    echo " -P Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K Keep the vagrant VM running after exiting"
    echo
    echo "e.g. build-toolchain.sh grisp2"
}

# Parse script's arguments
OPTIND=1
ARG_TARGET=""
ARG_DEBUG="${DEBUG:-0}"
ARG_CLEAN=false
ARG_FORCE_VAGRANT=false
ARG_PROVISION_VAGRANT=false
ARG_KEEP_VAGRANT=false
while getopts "hdcVPK" opt; do
    case "$opt" in
    d)
        ARG_DEBUG=1
        ;;
    c)
        ARG_CLEAN=true
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
    echo "ERROR: Missing arguments"
    show_usage
    exit 1
fi
ARG_TARGET="$1"
shift
if [[ $# > 0 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"
set_debug_level "$ARG_DEBUG"

if [[ $ARG_FORCE_VAGRANT = true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    VAGRANT_EXPERIMENTAL="disks" vagrant up
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
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    vagrant exec /home/vagrant/build-toolchain.sh "${NEW_ARGS[@]}"
    exit $?
fi

TOOLCHAIN_DEFCONFIG="$GLB_TOOLCHAIN_DIR/configs/${GLB_TARGET_NAME}_${BUILD_OS}_${BUILD_ARCH}_defconfig"

if [[ ! -e $TOOLCHAIN_DEFCONFIG ]]; then
    error 1 "Cannot find toolchain configuration $TOOLCHAIN_DEFCONFIG"
fi

TOOLCHAIN=$( read_defconfig_key $TOOLCHAIN_DEFCONFIG GLB_TOOLCHAIN_TYPE )

TOOLCHAIN_BUILD_SCRIPT="${GLB_TOOLCHAIN_SCRIPT_DIR}/build-${TOOLCHAIN}.sh"
if [[ ! -x $TOOLCHAIN_BUILD_SCRIPT ]]; then
    error 1 "Cannot find toolchain build script $TOOLCHAIN_BUILD_SCRIPT"
fi

CLEAN=$ARG_CLEAN GLB_TOP_DIR="${GLB_TOP_DIR}" $TOOLCHAIN_BUILD_SCRIPT "$GLB_TARGET_NAME" "$TOOLCHAIN_DEFCONFIG"
