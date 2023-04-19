#!/usr/bin/env bash

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-firmware.sh [-h] [-d] [-c] [-i] [-V] [-P] [-K] TARGET ERLANG_PROJECT_DIR [REBAR3_PROFILE]"
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start from scratch"
    echo " -i Generate an image in addition of the firmware"
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
ARG_GEN_IMAGE=false
ARG_FORCE_VAGRANT=false
ARG_KEEP_VAGRANT=false
while getopts "hdciVPK" opt; do
    case "$opt" in
    d)
        ARG_DEBUG=1
        ;;
    c)
        ARG_CLEAN=true
        ;;
    i)
        ARG_GEN_IMAGE=true
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
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"

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

if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    VAGRANT_TOP_DIR="/home/vagrant"
    VAGRANT_PROJECT_DIR="${VAGRANT_TOP_DIR}/projects/${PROJECT_NAME}"
    VAGRANT_EXPERIMENTAL="disks" vagrant up
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
    if [[ $ARG_GEN_IMAGE == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-i" )
    fi
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$VAGRANT_PROJECT_DIR" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_PROJECT_PROFILE" )
    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec "${VAGRANT_TOP_DIR}/build-firmware.sh" "${NEW_ARGS[@]}"
    exit $?
fi

if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$GLB_SDK_BASE_DIR/*"
fi

if [[ ! -d $GLB_SDK_DIR ]]; then
    echo "SDK not installed, trying to install it from artefacts..."
    if [[ ! -f "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}" ]]; then
        error 1 "SDK ${GLB_SDK_FILENAME} not found in ${GLB_ARTEFACTS_DIR}"
    fi
    if [[ ! -d $GLB_SDK_BASE_DIR ]]; then
        sudo mkdir -p "$GLB_SDK_BASE_DIR"
        sudo chgrp "$USER" "$GLB_SDK_BASE_DIR"
        sudo chmod 775 "$GLB_SDK_BASE_DIR"
    fi
    tar -C "$GLB_SDK_BASE_DIR" --strip-components=1 -xzf \
        "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}"
    if [[ ! -d $GLB_SDK_DIR ]]; then
        error 1 "SDK ${GLB_SDK_FILENAME} is invalid"
    fi
fi

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

if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$PROJECT_DIR"
    rm -rf "$FIRMWARE_DIR"
fi

mkdir -p "$PROJECT_DIR"
${RSYNC_CMD[@]} "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/${VCS_TAG_FILE}" ]] \
        && [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
    "${GLB_SCRIPT_DIR}/git-info.sh" -c "$SOURCE_PROJECT_DIR" \
        -o "$PROJECT_DIR/${VCS_TAG_FILE}"
fi
mkdir -p "$FIRMWARE_DIR"

cd "$PROJECT_DIR"
PROJECT_VCS_TAG="unknown"
if [[ -f "$VCS_TAG_FILE" ]]; then
    PROJECT_VCS_TAG="$( cat "$VCS_TAG_FILE" )"
fi
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"
rm -rf "_build/"
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
IMAGE_FILENAME="${BASE_FILENAME}.img"
IMAGE_FILE="${GLB_ARTEFACTS_DIR}/${IMAGE_FILENAME}"

# Create a base priority file
SQUASHFS_PRIORITIES="$FIRMWARE_DIR/squashfs.priority"
cat > "$SQUASHFS_PRIORITIES" <<EOF
boot/zImage 32764
boot/oftree 32763
sbin/init 32762
etc/erlinit.config 32761
EOF

# TODO: Allows for custom project-defined priorities

# Update the file system bundle
echo "Updating base firmware image with Erlang release..."

# Construct the proper path for the Erlang/OTP release
ERLANG_OVERLAY_DIR="${FIRMWARE_DIR}/rootfs_overlay/srv/erlang"
rm -rf "$ERLANG_OVERLAY_DIR"
mkdir -p "$ERLANG_OVERLAY_DIR"
cp -R "${RELEASE_DIR}/." "$ERLANG_OVERLAY_DIR"

# Clean up the Erlang release of all the files that we don't need.
"${GLB_COMMON_SYSTEM_DIR}/scripts/scrub-otp-release.sh" \
    "$FIRMWARE_DIR/rootfs_overlay/srv/erlang"

# TODO: Allows for custom project-defined overlay

# Merge the Erlang/OTP release onto the base image
"${GLB_COMMON_SYSTEM_DIR}/scripts/merge-squashfs.sh" \
    "$SDK_ROOTFS" "${FIRMWARE_DIR}/combined.squashfs" \
    "${FIRMWARE_DIR}/rootfs_overlay" "$SQUASHFS_PRIORITIES"

# Build the firmware image
echo "Building firmware $FIRMWARE_FILENAME..."
mkdir -p "$( dirname "$FIRMWARE_FILE" )"
GRISP_FW_DESCRIPTION="$APP_NAME" \
GRISP_FW_VERSION="${GLB_COMMON_SYSTEM_VER}-${GLB_TARGET_SYSTEM_VER}-${APP_VER}" \
GRISP_FW_PLATFORM="$GLB_TARGET_NAME" \
GRISP_FW_ARCHITECTURE="$CROSSCOMPILE_ARCH" \
GRISP_FW_VCS_IDENTIFIER="$GLB_VCS_TAG/$PROJECT_VCS_TAG" \
GRISP_SYSTEM="$GLB_SDK_DIR" \
ROOTFS="${FIRMWARE_DIR}/combined.squashfs" \
    fwup -c -f "$SDK_FWUP_CONFIG" -o "$FIRMWARE_FILE"

if [[ $ARG_GEN_IMAGE == true ]]; then
    echo "Building image $IMAGE_FILENAME..."
    mkdir -p "$( dirname "$IMAGE_FILE" )"

    # Erase the image file in case it exists from a previous build.
    # We use fwup in "programming" mode to create the raw image so it expects there
    # the destination to exist (like an MMC device). This provides the minimum sized image.
    rm -f "$IMAGE_FILE"
    touch "$IMAGE_FILE"

    # Build the raw image for the bulk programmer
    fwup -a -d "$IMAGE_FILE" -t complete -i "$FIRMWARE_FILE"
fi

echo "Done"
