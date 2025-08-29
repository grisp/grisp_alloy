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
    echo "USAGE: build-firmware.sh [-h] [-d] [-c] [-i] [-V] [-P] [-K] TARGET PROJECT_ARTEFACT [SERIAL_NUMBER]"
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
ARG_SERIAL_DEFINED=false
ARG_SERIAL="00000000"
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
    echo "ERROR: Missing target name"
    show_usage
    exit 1
fi
ARG_TARGET="$1"
shift
if [[ $# -eq 0 ]]; then
    echo "ERROR: Missing project artefact (tarball path or artefact name prefix)"
    show_usage
    exit 1
fi
ARG_ARTEFACT="$1"
shift
if [[ $# -gt 0 ]]; then
    ARG_SERIAL_DEFINED=true
    ARG_SERIAL="$1"
    shift
fi
if [[ $# -gt 0 ]]; then
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

PROJECT_NAME="unknown"
VCS_TAG_FILE=".alloy_vcs_tag"

set_debug_level "$ARG_DEBUG"

probe_tarball_target() {
    local tarfile="$1"
    local tmp_manifest proj_target manifest_path
    manifest_path="$( tar -tzf "$tarfile" 2>/dev/null | grep -E '^(\./)?ALLOY-PROJECT$' | head -n1 )"
    if [[ -z "$manifest_path" ]]; then
        echo ""
        return 2
    fi
    tmp_manifest="$(mktemp)"
    if ! tar -xzf "$tarfile" -O "$manifest_path" > "$tmp_manifest" 2>/dev/null; then
        rm -f "$tmp_manifest"
        echo ""
        return 2
    fi
    proj_target=$( ( set -a; source "$tmp_manifest"; echo "$PROJECT_TARGET_NAME" ) 2>/dev/null )
    rm -f "$tmp_manifest"
    echo "$proj_target"
    if [[ -z "$proj_target" ]]; then
        return 2
    fi
    return 0
}

resolve_tarball() {
    local -n resref="$1"
    local spec="$2"
    if [[ "$spec" == *.tgz && -f "$spec" ]]; then
        local abs proj_target
        abs="$( cd "$( dirname "$spec" )" && pwd )/$( basename "$spec" )"
        proj_target="$(probe_tarball_target "$abs")"
        if [[ $? -ne 0 ]]; then
            error 1 "Invalid project package: missing ALLOY-PROJECT or PROJECT_TARGET_NAME in $(basename "$abs")"
        fi
        if [[ "$proj_target" != "$GLB_TARGET_NAME" ]]; then
            error 1 "No valid project package found for selected target '$GLB_TARGET_NAME' (got '$proj_target')"
        fi
        resref="$abs"
        return 0
    fi
    local matches
    matches=( $( ls -1 "${GLB_ARTEFACTS_DIR}/${spec}"*.tgz 2>/dev/null || true ) )
    if [[ ${#matches[@]} -eq 0 ]]; then
        error 1 "No artefact matching prefix '${spec}'. Build the project with build-project.sh first."
    elif [[ ${#matches[@]} -gt 1 ]]; then
        # Filter by manifest target in ALLOY-PROJECT
        local filtered=( )
        for m in "${matches[@]}"; do
            local proj_target
            proj_target="$(probe_tarball_target "$m")"
            if [[ $? -ne 0 ]]; then
                echo "WARNING: Invalid project package: missing ALLOY-PROJECT or PROJECT_TARGET_NAME in $(basename "$m")" 1>&2
                continue
            fi
            if [[ "$proj_target" == "$GLB_TARGET_NAME" ]]; then
                filtered+=("$m")
            fi
        done
        if [[ ${#filtered[@]} -eq 1 ]]; then
            resref="${filtered[0]}"
            return 0
        elif [[ ${#filtered[@]} -eq 0 ]]; then
            error 1 "No project package found for selected target '$GLB_TARGET_NAME'"
        else
            echo "WARNING: Multiple artefacts found for prefix '${spec}' (matching target '${GLB_TARGET_NAME}'):" 1>&2
            for m in "${filtered[@]}"; do echo "  $( basename "$m" )"; done
            error 1 "Multiple project options error"
        fi
    else
        # Single match: still validate by manifest
        local only="${matches[0]}" proj_target
        proj_target="$(probe_tarball_target "$only")"
        if [[ $? -ne 0 ]]; then
            error 1 "Invalid project package: missing ALLOY-PROJECT or PROJECT_TARGET_NAME in $(basename "$only")"
        fi
        if [[ "$proj_target" != "$GLB_TARGET_NAME" ]]; then
            error 1 "No project package found for selected target '$GLB_TARGET_NAME' (got '$(basename "$only")' with '$proj_target')"
        fi
        resref="$only"
    fi
}

resolve_tarball PROJECT_FILEPATH "$ARG_ARTEFACT"
PROJECT_FILENAME="$( basename "$PROJECT_FILEPATH" )"
PROJECT_NAME="$( echo "$PROJECT_FILENAME" | sed "s|\(.*\)-.*\.tgz|\1|" )"

# VAGRANT VM EXECUTION BLOCK
# Non-Linux hosts (macOS, etc.) or forced Vagrant mode require VM execution
# This entire block sets up VM, syncs project files, and re-executes script inside VM
if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    vagrant ssh-config > .vagrant.ssh_config
    # If artefact is under GLB_ARTEFACTS_DIR, use the synced path within VM, preserving subdirectories
    if [[ "$PROJECT_FILEPATH" == ${GLB_ARTEFACTS_DIR}/* ]]; then
        REL_PATH="${PROJECT_FILEPATH#${GLB_ARTEFACTS_DIR}/}"
        NEW_PROJECT_FILEPATH="${GLB_VAGRANT_TOP_DIR}/artefacts/${REL_PATH}"
    else
        vagrant exec mkdir -p "$VAGRANT_FIRMWARE_BUILD_DIR"
        rsync -av -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" "$PROJECT_FILEPATH" "vagrant@default:${VAGRANT_FIRMWARE_BUILD_DIR}/${PROJECT_FILENAME}"
        NEW_PROJECT_FILEPATH="${VAGRANT_FIRMWARE_BUILD_DIR}/${PROJECT_FILENAME}"
    fi

    # Keep track of the alloy VCS tag
    if [[ -d "$GLB_TOP_DIR/.git" ]]; then
        GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$GLB_TOP_DIR" )"
        echo "$GLB_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${GLB_VAGRANT_TOP_DIR}/${VCS_TAG_FILE}"
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
    NEW_ARGS=( ${NEW_ARGS[@]} "$NEW_PROJECT_FILEPATH" )

    if [[ $ARG_SERIAL_DEFINED == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_SERIAL" )
    fi

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-firmware.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE

# Clean SDK if requested (forces full rebuild)
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$GLB_SDK_BASE_DIR/*"
fi

# SDK INSTALLATION
install_sdk

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
source "${GLB_SCRIPT_DIR}/plugins/bootscheme.sh"
bootscheme_setup ${BOOTSCHEME}

# PROJECT ARTEFACT PREPARATION
PROJECT_DIR="${GLB_FIRMWARE_BUILD_DIR}/projects/${PROJECT_NAME}"
FIRMWARE_DIR="${GLB_FIRMWARE_BUILD_DIR}/firmwares/${PROJECT_NAME}"
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

mkdir -p "$PROJECT_DIR"
mkdir -p "$FIRMWARE_DIR"

# Unpack project tarball under PROJECT_DIR
tar -xzf "$PROJECT_FILEPATH" -C "$PROJECT_DIR"

# Read manifest
MANIFEST_FILE="${PROJECT_DIR}/ALLOY-PROJECT"
if [[ ! -f "$MANIFEST_FILE" ]]; then
    error 1 "Missing manifest ALLOY-PROJECT in artefact"
fi
source "$MANIFEST_FILE"
PROJECT_VCS_TAG="${PROJECT_VCS_PROJECT:-unknown}"

# Validate target and environment compatibility
if [[ "$PROJECT_TARGET_NAME" != "$GLB_TARGET_NAME" ]]; then
    error 1 "Artefact target '$PROJECT_TARGET_NAME' does not match requested target '$GLB_TARGET_NAME'"
fi

# Validate system versions and arch if present
if [[ -n "$PROJECT_COMMON_SYSTEM_VER" && -n "$GLB_COMMON_SYSTEM_VER" && "$PROJECT_COMMON_SYSTEM_VER" != "$GLB_COMMON_SYSTEM_VER" ]]; then
    error 1 "Artefact common system version '$PROJECT_COMMON_SYSTEM_VER' does not match '$GLB_COMMON_SYSTEM_VER'"
fi
if [[ -n "$PROJECT_TARGET_SYSTEM_VER" && -n "$GLB_TARGET_SYSTEM_VER" && "$PROJECT_TARGET_SYSTEM_VER" != "$GLB_TARGET_SYSTEM_VER" ]]; then
    error 1 "Artefact target system version '$PROJECT_TARGET_SYSTEM_VER' does not match '$GLB_TARGET_SYSTEM_VER'"
fi

# Prepare cross-compile environment for scrub and packaging
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"
if [[ -n "$PROJECT_ARCH" && -n "$CROSSCOMPILE_ARCH" && "$PROJECT_ARCH" != "$CROSSCOMPILE_ARCH" ]]; then
    error 1 "Artefact arch '$PROJECT_ARCH' does not match '$CROSSCOMPILE_ARCH'"
fi

# Locate release directory inside artefact
RELEASE_DIR="${PROJECT_DIR}/release"
if [[ ! -d "$RELEASE_DIR" ]]; then
    error 1 "Invalid artefact: missing 'release' directory"
fi

APP_NAME="${PROJECT_APP_NAME}"
APP_VER="${PROJECT_APP_VERSION:-}"
if [[ -z "$APP_VER" ]]; then
    APP_REL_DIR=$( echo "${RELEASE_DIR}/lib/${APP_NAME}-"* )
    if [[ -d $APP_REL_DIR ]]; then
        APP_VER="$( echo "$APP_REL_DIR" | sed "s|^.*/${APP_NAME}-\(.*\)$|\1|" )"
    fi
fi

BASE_FILENAME="${APP_NAME}"
if [[ -n "${APP_VER}" ]]; then
    BASE_FILENAME="${BASE_FILENAME}-${APP_VER}"
fi
BASE_FILENAME="${BASE_FILENAME}-${GLB_TARGET_NAME}"
if [[ -n "${PROJECT_PROFILE}" && "${PROJECT_PROFILE}" != "default" ]]; then
    BASE_FILENAME="${BASE_FILENAME}-${PROJECT_PROFILE}"
fi

FIRMWARE_FILENAME="${BASE_FILENAME}.fw"
FIRMWARE_FILE="${GLB_ARTEFACTS_DIR}/${FIRMWARE_FILENAME}"
IMAGE_BASE_FILENAME="${BASE_FILENAME}"
IMAGE_BASE_FILE="${GLB_ARTEFACTS_DIR}/${IMAGE_BASE_FILENAME}"
IMAGE_FILE_EXTENSION=".img"

# Create a consolidated priority file (project + firmware)
SQUASHFS_PRIORITIES_FILE="$FIRMWARE_DIR/squashfs.priority"
rm -f "$SQUASHFS_PRIORITIES_FILE"
PRIO_TEMP="$FIRMWARE_DIR/.priorities.tmp"
PRIO_PATHS="$FIRMWARE_DIR/.prio.paths"
rm -f "$PRIO_TEMP" "$PRIO_PATHS"

# 1) Project-defined priorities
PROJECT_PRIORITIES_FILE="${PROJECT_DIR}/ALLOY-FS-PRIORITIES"
if [[ -f "$PROJECT_PRIORITIES_FILE" ]]; then
    cat "$PROJECT_PRIORITIES_FILE" >> "$PRIO_TEMP"
fi

# 2) Firmware priorities, but skip duplicates present in project file
if [[ -f "$PROJECT_PRIORITIES_FILE" ]]; then
    awk '{print $1}' "$PROJECT_PRIORITIES_FILE" | sort -u > "$PRIO_PATHS"
else
    : > "$PRIO_PATHS"
fi

for ((i = 0; i < ${#SQUASHFS_PRIORITIES[@]}; i += 2 )); do
    p="${SQUASHFS_PRIORITIES[i]}"
    w="${SQUASHFS_PRIORITIES[i + 1]}"
    if ! grep -qx -- "$p" "$PRIO_PATHS" 2>/dev/null; then
        echo "$p $w" >> "$PRIO_TEMP"
    fi
done

# Sort by weight desc for readability
if [[ -s "$PRIO_TEMP" ]]; then
    sort -k2,2nr -o "$SQUASHFS_PRIORITIES_FILE" "$PRIO_TEMP"
else
    : > "$SQUASHFS_PRIORITIES_FILE"
fi
rm -f "$PRIO_TEMP" "$PRIO_PATHS"

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
NAME="${OS_RELEASE_NAME:="${GLB_TARGET_NAME}-${PROJECT_APP_NAME}"}"
PRETTY_NAME="${OS_RELEASE_PRETTY_NAME:="${GLB_TARGET_NAME}-${PROJECT_APP_NAME}"}"
ID="${OS_RELEASE_ID:=${GLB_TARGET_NAME}}"
VERSION="${GLB_COMMON_SYSTEM_VER}-${GLB_COMMON_SYSTEM_VER}"
EOF

# Generate alloy manifest
ALLOY_FIRMWARE_FILE="${FIRMWARE_DIR}/rootfs_overlay/alloy-firmware.json"
mkdir -p $( dirname $ALLOY_FIRMWARE_FILE )
cat << EOF > "$ALLOY_FIRMWARE_FILE"
{
    "architecture": "${CROSSCOMPILE_ARCH}",
    "serial": "${ARG_SERIAL}",
    "target": "${GLB_TARGET_NAME}",
    "system_common_version": "${GLB_COMMON_SYSTEM_VER}",
    "system_common_vcs": "${GLB_VCS_TAG}",
    "system_target_version": "${GLB_TARGET_SYSTEM_VER}",
    "system_target_vcs": "${GLB_VCS_TAG}",
    "projects": {
        "${PROJECT_APP_NAME}": {
            "version": "${PROJECT_APP_VERSION}",
            "vcs": "${PROJECT_VCS_TAG}",
            "type": "${PROJECT_TYPE}",
            "profile": "${PROJECT_PROFILE}"
        }
    }
}
EOF

cat $OS_RELEASE_FILE
cat $ALLOY_FIRMWARE_FILE

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
