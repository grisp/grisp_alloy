#!/usr/bin/env bash

# build-ramfs.sh - GRiSP Alloy initramfs artifact builder

set -e

BR_VERSION="2025.05"

show_usage()
{
    echo "USAGE: build-ramfs.sh OPTIONS FLAVOUR"
    echo "OPTIONS:"
    echo " -h | --help"
    echo "    Show this."
    echo " -d | --debug"
    echo "    Print scripts debug information."
    echo " -b | --print-buildroot"
    echo "    Print the buildroot environment variables."
    echo " -r | --rebuild"
    echo "    Try running buildroot only, if possible."
    echo " -c | --clean"
    echo "    Cleanup the current ramfs flavour state and build from scratch."
    echo " -V | --force-vagrant"
    echo "    Use the Vagrant VM even on Linux."
    echo " -P | --provision"
    echo "    Re-provision the Vagrant VM."
    echo " -K | --keep-vagrant"
    echo "    Keep the Vagrant VM running after exiting."
    echo " -p | --clean-package <PACKAGE_PREFIX>"
    echo "    Clean given package prefix; can be used with --rebuild."
    echo " --external <DIR>"
    echo "    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs."
    echo
    echo "e.g. build-ramfs.sh kontron-albl-imx8mm-shell"
}

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
    echo "ERROR: Missing FLAVOUR"
    show_usage
    exit 1
fi
ARG_FLAVOUR="${POSITIONALS[0]}"
if [[ ${#POSITIONALS[@]} -gt 1 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

# Load common host/path helpers. Ramfs flavours are intentionally independent
# from system targets, so do not pass ARG_FLAVOUR as a target name.
source "$( dirname "$0" )/scripts/common.sh" ""
set_debug_level "$ARG_DEBUG"

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
    VAGRANT_EXTERNAL_DIRS=( )
    alloy_vagrant_sync_external_roots VAGRANT_EXTERNAL_DIRS
    for external_dir in "${VAGRANT_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
    done
    NEW_ARGS+=( "$ARG_FLAVOUR" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap 'cd "$GLB_TOP_DIR"; vagrant halt' EXIT
    fi
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-ramfs.sh" "${NEW_ARGS[@]}"
    exit $?
fi

if [[ $HOST_OS != "linux" ]]; then
    error 1 "${HOST_OS} is not supported, only linux"
fi

if [[ $HOST_ARCH != "x86_64" && $HOST_ARCH != "aarch64" ]]; then
    error 1 "$HOST_ARCH is not supported, only x86_64 or aarch64"
fi

alloy_resolve_ramfs_context "$ARG_FLAVOUR"

RAMFS_COMMON_DIR="${GLB_RAMFS_COMMON_DIR}"
RAMFS_FLAVOUR_DIR="${GLB_RAMFS_FLAVOUR_DIR}"
RAMFS_COMMON_DEFCONFIG="${RAMFS_COMMON_DIR}/defconfig"
RAMFS_FLAVOUR_DEFCONFIG="${RAMFS_FLAVOUR_DIR}/defconfig"

if [[ ! -d "$RAMFS_COMMON_DIR" ]]; then
    error 1 "Common ramfs directory not found: ${RAMFS_COMMON_DIR}"
fi
if [[ ! -d "$RAMFS_FLAVOUR_DIR" ]]; then
    error 1 "Ramfs flavour ${ARG_FLAVOUR} not supported, directory not found: ${RAMFS_FLAVOUR_DIR}"
fi
if [[ ! -f "$RAMFS_COMMON_DEFCONFIG" ]]; then
    error 1 "File not found: ${RAMFS_COMMON_DEFCONFIG}"
fi
if [[ ! -f "$RAMFS_FLAVOUR_DEFCONFIG" ]]; then
    error 1 "File not found: ${RAMFS_FLAVOUR_DEFCONFIG}"
fi

RAMFS_COMMON_VER="$GLB_RAMFS_COMMON_VER"
RAMFS_FLAVOUR_VER="$GLB_RAMFS_FLAVOUR_VER"
RAMFS_CACHE_DIR="${GLB_TOP_DIR}/_cache/ramfs"
RAMFS_BUILD_ROOT="${GLB_TOP_DIR}/_build/ramfs/${ARG_FLAVOUR}"
BUILDROOT_PATH="${RAMFS_BUILD_ROOT}/buildroot"
BUILD_DIR="${RAMFS_BUILD_ROOT}/build"
FINAL_DEFCONFIG="${BUILD_DIR}/defconfig"
CHECKPOINTS_DIR="${RAMFS_BUILD_ROOT}/checkpoints"
RAMFS_FILENAME="grisp_alloy_ramfs-${ARG_FLAVOUR}-${RAMFS_COMMON_VER}-${RAMFS_FLAVOUR_VER}-${HOST_OS}-${HOST_ARCH}.cpio.gz"
RAMFS_ARTIFACT="${GLB_ARTEFACTS_DIR}/${RAMFS_FILENAME}"

BUILDROOT_MAKE_PARAMS=(
    -C "$BUILDROOT_PATH" \
    O="$BUILD_DIR" \
    BR2_EXTERNAL="$RAMFS_COMMON_DIR" \
    BR2_DEFCONFIG="$FINAL_DEFCONFIG" \
    GRISP_TOP_DIR="$GLB_TOP_DIR" \
    GRISP_RAMFS_COMMON_DIR="$RAMFS_COMMON_DIR" \
    GRISP_RAMFS_FLAVOUR_DIR="$RAMFS_FLAVOUR_DIR" \
    GRISP_RAMFS_FLAVOUR="$ARG_FLAVOUR" \
    GRISP_BUILD_HOST_ARCH="$HOST_ARCH" \
    GLB_DEBUG="$GLB_DEBUG"
)

if [[ $ARG_DEBUG -gt 0 ]]; then
    BUILDROOT_MAKE_PARAMS+=( "V=1" )
fi

if [[ $ARG_BRCMD == "true" ]]; then
    echo "Buildroot command:"
    echo "make ${BUILDROOT_MAKE_PARAMS[*]}"
    exit 0
fi

if [[ $ARG_CLEAN == "true" ]]; then
    rm -rf "$RAMFS_BUILD_ROOT"
fi

if [[ $ARG_REBUILD == "true" ]]; then
    rm -f "${CHECKPOINTS_DIR}/prepare_buildroot"
    rm -f "${CHECKPOINTS_DIR}/run_buildroot"
fi

for p in "${ARG_CLEAN_PACKAGES[@]}"; do
    echo rm -rf "${BUILD_DIR}/build/${p}"*
    rm -rf "${BUILD_DIR}/build/${p}"*
done

prepare_environment()
{
    echo "Preparing ramfs environment..."
    mkdir -p "$GLB_ARTEFACTS_DIR"
    mkdir -p "$RAMFS_BUILD_ROOT"
    mkdir -p "$RAMFS_CACHE_DIR"
    mkdir -p "$CHECKPOINTS_DIR"
    mkdir -p "$BUILD_DIR"
}

checkout_source_code()
{
    local extracted_dir="${RAMFS_BUILD_ROOT}/buildroot-${BR_VERSION}"
    local tarball_name="buildroot-${BR_VERSION}.tar.gz"
    local tarball_path="${GLB_ARTEFACTS_DIR}/${tarball_name}"

    git lfs checkout || (echo "Error: please install git lfs!" && exit 1)

    rm -fr "$extracted_dir" "$BUILDROOT_PATH"

    if [[ ! -e "$tarball_path" ]]; then
        echo "Downloading buildroot ${BR_VERSION}..."
        if [[ $BR_VERSION =~ 20[0-9][0-9]\.[0-1][0-9] ]]; then
            local download_url="https://buildroot.org/downloads/${tarball_name}"
        else
            local download_url="https://git.busybox.net/buildroot/snapshot/${tarball_name}"
        fi
        cd "${GLB_ARTEFACTS_DIR}"
        wget "$download_url"
        local ret="$?"
        if [[ $ret != 0 ]]; then
            error $ret "Failed to download ${tarball_name} from location ${download_url}"
        fi
    else
        echo "Buildroot ${BR_VERSION} already cached."
    fi

    echo "Extracting buildroot ${BR_VERSION}..."
    mkdir -p "$extracted_dir"
    tar xzf "$tarball_path" -C "$extracted_dir" --strip-components=1
    ln -s "$extracted_dir" "$BUILDROOT_PATH"

    echo "Applying buildroot ${BR_VERSION} patches..."
    if [[ -d "${RAMFS_COMMON_DIR}/patches/buildroot" ]]; then
        "${BUILDROOT_PATH}/support/scripts/apply-patches.sh" "${BUILDROOT_PATH}" "${RAMFS_COMMON_DIR}/patches/buildroot"
    fi

    ln -sf "$RAMFS_CACHE_DIR" "${BUILDROOT_PATH}/dl"
}

prepare_buildroot()
{
    cat > "$FINAL_DEFCONFIG" << EOF
########## GENERATED BY BUILD-RAMFS SCRIPT

########## FROM COMMON RAMFS ${RAMFS_COMMON_VER}
$( cat "$RAMFS_COMMON_DEFCONFIG" )

########## FROM ${ARG_FLAVOUR} RAMFS ${RAMFS_FLAVOUR_VER}
$( cat "$RAMFS_FLAVOUR_DEFCONFIG" )
EOF

    echo "Configuring ramfs flavour $ARG_FLAVOUR..."
    make "${BUILDROOT_MAKE_PARAMS[@]}" defconfig
}

run_buildroot()
{
    echo "Run buildroot for ramfs flavour $ARG_FLAVOUR..."
    make "${BUILDROOT_MAKE_PARAMS[@]}"
}

make_ramfs_artifact()
{
    local cpio="${BUILD_DIR}/images/rootfs.cpio.gz"
    if [[ ! -f "$cpio" ]]; then
        error 1 "Buildroot did not produce expected ramfs artifact: ${cpio}"
    fi
    mkdir -p "$GLB_ARTEFACTS_DIR"
    cp "$cpio" "$RAMFS_ARTIFACT"
    echo "Ramfs artifact: $RAMFS_ARTIFACT"
}

checkpoint prepare_environment "$CHECKPOINTS_DIR"
checkpoint checkout_source_code "$CHECKPOINTS_DIR"
checkpoint prepare_buildroot "$CHECKPOINTS_DIR"
checkpoint run_buildroot "$CHECKPOINTS_DIR"
make_ramfs_artifact

echo "Done"
