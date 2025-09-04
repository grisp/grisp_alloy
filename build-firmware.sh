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
# 5. Resolve and unpack one or more project artefacts
# 6. Stage each project under /srv/alloy/<name> and create /srv/erlang symlink
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
    echo "USAGE: build-firmware.sh [-h] [-d] [-c] [-i] [-V] [-P] [-K] [-s SERIAL] [-n NAME] [-o OVERLAY_DIR] TARGET (ARTEFACT_PREFIX | ARTEFACT_PATH [--name NAME])..."
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start from scratch"
    echo " -i Generate raw images in addition of the firmware"
    echo " -V Using the Vagrant VM even on Linux"
    echo " -P Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K Keep the vagrant VM running after exiting"
    echo " -s Device serial number"
    echo " -n Firmware name (defaults to first artefact's base name)"
    echo " -o Overlay directory to merge into rootfs before packaging"
    echo
    echo "Examples:"
    echo "  build-firmware.sh grisp2 projA"
    echo "  build-firmware.sh grisp2 projA --name alpha projB --name beta"
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
ARG_FIRMWARE_NAME=""
while getopts "hdciVs:n:o:PK" opt; do
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
    s)
        ARG_SERIAL_DEFINED=true
        ARG_SERIAL="$OPTARG"
        ;;
    n)
        ARG_FIRMWARE_NAME="$OPTARG"
        ;;
    o)
        ARG_OVERLAY_DIR="$OPTARG"
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
# Validate overlay dir on host if provided
if [[ -n "$ARG_OVERLAY_DIR" ]]; then
    if [[ ! -d "$ARG_OVERLAY_DIR" ]]; then
        error 1 "Overlay directory not found: $ARG_OVERLAY_DIR"
    fi
fi

# Remaining tokens (could be NODE/PROJECT specs). We validate later.
RAW_TOKENS=( "$@" )

# Load common variables and functions (GLB_* globals, error handling, etc.)
source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"

# Validate host architecture - only modern 64-bit architectures supported
if [[ $HOST_ARCH != "x86_64" && $HOST_ARCH != "aarch64" && $HOST_ARCH != "arm64" ]]; then
    error 1 "$HOST_ARCH is not supported, only x86_64, aarch64 or arm64"
fi

FIRMWARE_NAME=""
OVERLAY_DIR=""
VCS_TAG_FILE=".alloy_vcs_tag"

set_debug_level "$ARG_DEBUG"

# Arrays describing projects to stage
PROJECT_NAMES=( )
PROJECT_REFS=( )
PROJECT_ARTEFACTS=( )

parse_projects() {
    local tokens=( "${RAW_TOKENS[@]}" )
    local current_node_idx=-1
    local artefact_path

    local i=0
    while [[ $i -lt ${#tokens[@]} ]]; do
        case "${tokens[$i]}" in
            --name)
                if [[ $current_node_idx -lt 0 ]]; then
                    error 1 "--name must be used after a project reference"
                fi
                i=$(( i + 1 ))
                if [[ $i -ge ${#tokens[@]} ]]; then
                    error 1 "--name requires a value"
                fi
                PROJECT_NAMES[$current_node_idx]="${tokens[$i]}"
                ;;
            --*)
                error 1 "Unknown option: ${tokens[$i]}"
                ;;
            *)
                current_node_idx=$((current_node_idx + 1))
                PROJECT_REFS[$current_node_idx]="${tokens[$i]}"
                artefact_path="$( resolve_tarball "${tokens[$i]}" )"
                if [[ -z "${PROJECT_NAMES[$current_node_idx]}" ]]; then
                    PROJECT_NAMES[$current_node_idx]="$( artefact_info PROJECT_APP_NAME "$artefact_path" )"
                fi
                PROJECT_ARTEFACTS[$current_node_idx]="$artefact_path"
                ;;
        esac
        i=$(( i + 1 ))
    done
}

artefact_info() {
    # Usage: artefact_info VAR_NAME TARFILE → echoes value of VAR_NAME from ALLOY-PROJECT
    local var_name="$1"
    local tarfile="$2"
    local tmp_manifest
    local val
    tmp_manifest="$(mktemp)"
    if ! tar -xzf "$tarfile" -O "./ALLOY-PROJECT" > "$tmp_manifest" 2>/dev/null; then
        rm -f "$tmp_manifest"
        error 3 "Invalid project package: missing ALLOY-PROJECT in $(basename "$tarfile")"
    fi
    val=$( ( set -a; source "$tmp_manifest"; echo "${!var_name}" ) 2>/dev/null )
    rm -f "$tmp_manifest"
    if [[ -z "$val" ]]; then
        error 4 "Invalid project package: missing ${var_name} in $(basename "$tarfile")"
    fi
    echo "$val"
}

resolve_tarball() {
    local spec="$1"
    local path
    local proj_target
    local matches
    local filtered=( )
    if [[ "$spec" == *.tgz && -f "$spec" ]]; then
        path="$( cd "$( dirname "$spec" )" && pwd )/$( basename "$spec" )"
        proj_target="$( artefact_info PROJECT_TARGET_NAME "$path" )"
        if [[ "$proj_target" != "$GLB_TARGET_NAME" ]]; then
            error 1 "No valid project package found for selected target '$GLB_TARGET_NAME' (got '$proj_target')"
        fi
        echo "$path"
        return 0
    fi
    matches=( $( ls -1 "${GLB_ARTEFACTS_DIR}/${spec}"*.tgz 2>/dev/null || true ) )
    if [[ ${#matches[@]} -eq 0 ]]; then
        error 1 "No artefact matching prefix '${spec}'. Build the project with build-project.sh first."
    elif [[ ${#matches[@]} -gt 1 ]]; then
        # Filter by manifest target in ALLOY-PROJECT
        for m in "${matches[@]}"; do
            proj_target="$( artefact_info PROJECT_TARGET_NAME "$m" )"
            if [[ "$proj_target" == "$GLB_TARGET_NAME" ]]; then
                filtered+=("$m")
            fi
        done
        if [[ ${#filtered[@]} -eq 1 ]]; then
            echo "${filtered[0]}"
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
        path="${matches[0]}"
        proj_target="$( artefact_info PROJECT_TARGET_NAME "$path" )"
        if [[ "$proj_target" != "$GLB_TARGET_NAME" ]]; then
            error 1 "No project package found for selected target '$GLB_TARGET_NAME' (got '$(basename "$path")' with '$proj_target')"
        fi
        echo "$path"
        return 0
    fi
}

parse_projects

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

    # Map each project tarball to an in-VM path and upload if needed
    vagrant exec mkdir -p "$GLB_VAGRANT_FIRMWARE_BUILD_DIR/uploads"

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
    if [[ $ARG_SERIAL_DEFINED == true ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-s" "$ARG_SERIAL" )
    fi
    if [[ -n "$ARG_FIRMWARE_NAME" ]]; then
        NEW_ARGS=( ${NEW_ARGS[@]} "-n" "$ARG_FIRMWARE_NAME" )
    fi
    if [[ -n "$ARG_OVERLAY_DIR" ]]; then
        # Sync overlay dir to VM uploads/overlay and pass translated path
        vagrant exec rm -rf "$GLB_VAGRANT_FIRMWARE_BUILD_DIR/overlay"
        vagrant exec mkdir -p "$GLB_VAGRANT_FIRMWARE_BUILD_DIR/overlay"
        rsync -av -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" "$ARG_OVERLAY_DIR/" "vagrant@default:${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/overlay/"
        NEW_ARGS=( ${NEW_ARGS[@]} "-o" "${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/overlay" )
    fi
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )

    # Append per-project arguments (with VM-resolved artefact paths)
    for i in "${!PROJECT_ARTEFACTS[@]}"; do
        local_host_path="${PROJECT_ARTEFACTS[$i]}"
        if [[ "$local_host_path" == ${GLB_ARTEFACTS_DIR}/* ]]; then
            REL_PATH="${local_host_path#${GLB_ARTEFACTS_DIR}/}"
            NEW_ARGS+=( "${GLB_VAGRANT_ARTEFACTS_DIR}/${REL_PATH}" )
        else
            rsync -av -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" "$local_host_path" "vagrant@default:${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/uploads"
            NEW_ARGS+=( "${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/uploads/$( basename "$local_host_path" )" )
        fi
        if [[ -n "${PROJECT_NAMES[$i]}" ]]; then
            NEW_ARGS+=( "--name" "${PROJECT_NAMES[$i]}" )
        fi
    done

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-firmware.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE

# Determine firmware name
if [[ -n "$ARG_FIRMWARE_NAME" ]]; then
    FIRMWARE_NAME="$ARG_FIRMWARE_NAME"
else
    FIRMWARE_NAME="${PROJECT_NAMES[0]}"
fi

if [[ -n "$ARG_OVERLAY_DIR" ]]; then
    OVERLAY_DIR="$ARG_OVERLAY_DIR"
fi

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
PROJECTS_BASE_DIR="${GLB_FIRMWARE_BUILD_DIR}/projects"
FIRMWARE_DIR="${GLB_FIRMWARE_BUILD_DIR}/firmwares/${FIRMWARE_NAME}"
SDK_ROOTFS="$GLB_SDK_DIR/images/rootfs.squashfs"
SDK_FWUP_CONFIG="$GLB_SDK_DIR/images/fwup.conf"
GLB_VCS_TAG="unknown"
if [[ -d "${GLB_TOP_DIR}/.git" ]]; then
    GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$GLB_TOP_DIR" )"
elif [[ -f "${GLB_TOP_DIR}/${VCS_TAG_FILE}" ]]; then
    GLB_VCS_TAG="$( cat "${GLB_TOP_DIR}/${VCS_TAG_FILE}" )"
fi

if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$PROJECTS_BASE_DIR"
fi

rm -rf "$FIRMWARE_DIR"

mkdir -p "$PROJECTS_BASE_DIR"
mkdir -p "$FIRMWARE_DIR"

# Prepare cross-compile environment for scrub and packaging
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"

# Unpack and validate all projects
PROJECT_DIRS=( )
RELEASE_DIRS=( )
APP_NAMES=( )
APP_VERS=( )
REL_VERS=( )
PROJ_TYPES=( )
PROJ_PROFILES=( )
PROJ_VCS_TAGS=( )
ERTS_VERS=( )
PROJECT_ROOTS=( )

for idx in "${!PROJECT_ARTEFACTS[@]}"; do
    tarball="${PROJECT_ARTEFACTS[$idx]}"
    app_name="$( artefact_info PROJECT_APP_NAME "$tarball" )"
    proj_dir="${PROJECTS_BASE_DIR}/${PROJECT_NAMES[$idx]}"
    proj_root="/srv/alloy/${PROJECT_NAMES[$idx]}"
    rm -rf "$proj_dir"
    mkdir -p "$proj_dir"
    tar -xzf "$tarball" -C "$proj_dir"

    man_file="${proj_dir}/ALLOY-PROJECT"
    if [[ ! -f "$man_file" ]]; then
        error 1 "Missing manifest ALLOY-PROJECT in $app_name artefact"
    fi
    source "$man_file"

    if [[ "$PROJECT_TARGET_NAME" != "$GLB_TARGET_NAME" ]]; then
        error 1 "Artefact $app_name target '$PROJECT_TARGET_NAME' does not match requested target '$GLB_TARGET_NAME'"
    fi
    if [[ -n "$PROJECT_COMMON_SYSTEM_VER" && -n "$GLB_COMMON_SYSTEM_VER" && "$PROJECT_COMMON_SYSTEM_VER" != "$GLB_COMMON_SYSTEM_VER" ]]; then
        error 1 "Artefact $app_name common system version '$PROJECT_COMMON_SYSTEM_VER' does not match '$GLB_COMMON_SYSTEM_VER'"
    fi
    if [[ -n "$PROJECT_TARGET_SYSTEM_VER" && -n "$GLB_TARGET_SYSTEM_VER" && "$PROJECT_TARGET_SYSTEM_VER" != "$GLB_TARGET_SYSTEM_VER" ]]; then
        error 1 "Artefact $app_name target system version '$PROJECT_TARGET_SYSTEM_VER' does not match '$GLB_TARGET_SYSTEM_VER'"
    fi
    if [[ -n "$PROJECT_CROSSCOMPILE_ARCH" && -n "$CROSSCOMPILE_ARCH" && "$PROJECT_CROSSCOMPILE_ARCH" != "$CROSSCOMPILE_ARCH" ]]; then
        error 1 "Artefact $app_name arch '$PROJECT_CROSSCOMPILE_ARCH' does not match '$CROSSCOMPILE_ARCH'"
    fi

    rel_dir="${proj_dir}/release"
    if [[ ! -d "$rel_dir" ]]; then
        error 1 "Invalid $app_name artefact: missing 'release' directory"
    fi

    app_ver="${PROJECT_APP_VERSION:-}"
    if [[ -z "$app_ver" ]]; then
        app_rel_dir=$( echo "${rel_dir}/lib/${app_name}-"* )
        if [[ -d $app_rel_dir ]]; then
            app_ver="$( echo "$app_rel_dir" | sed "s|^.*/${app_name}-\(.*\)$|\1|" )"
        fi
    fi

    erts_dir_cand=$( echo "${rel_dir}/erts-"* )
    if [[ ! -d "$erts_dir_cand" ]] || [[ "$erts_dir_cand" == "${rel_dir}/erts-*" ]]; then
        error 1 "Missing release erts directory"
    fi
    if [[ -z "$app_ver" ]] || [[ ! -d "${rel_dir}/lib/${app_name}-${app_ver}" ]]; then
        error 1 "Missing release path lib/${app_name}-${app_ver}"
    fi
    # Determine release version from manifest if available; fallback to app_ver
    rel_version="${PROJECT_RELEASE_VERSION:-$app_ver}"
    if [[ -z "$rel_version" ]]; then
        # As a last resort, pick the first matching releases/${app_name}-*
        rel_match=$( echo "${rel_dir}/releases/${app_name}-"* )
        if [[ -d "$rel_match" ]] && [[ "$rel_match" != "${rel_dir}/releases/${app_name}-*" ]]; then
            rel_version="$( basename "$rel_match" | sed "s/^${app_name}-//" )"
        fi
    fi
    if [[ -z "$rel_version" ]] || [[ ! -d "${rel_dir}/releases/${rel_version}" ]]; then
        error 1 "Missing $app_name release path releases/${rel_version}"
    fi

    PROJECT_DIRS+=( "$proj_dir" )
    RELEASE_DIRS+=( "$rel_dir" )
    APP_NAMES+=( "$app_name" )
    APP_VERS+=( "$app_ver" )
    PROJ_TYPES+=( "${PROJECT_TYPE}" )
    PROJ_PROFILES+=( "${PROJECT_PROFILE}" )
    PROJ_VCS_TAGS+=( "${PROJECT_VCS_PROJECT:-unknown}" )
    ERTS_VERS+=( "$( basename "$erts_dir_cand" | sed 's/^erts-//' )" )
    REL_VERS+=( "$rel_version" )
    PROJECT_ROOTS+=( "$proj_root" )
done

if [[ ${#RELEASE_DIRS[@]} -eq 0 ]]; then
    error 1 "Missing project artefact (tarball path or artefact name prefix)"
fi

BASE_FILENAME="${FIRMWARE_NAME}-${GLB_TARGET_NAME}"
FIRMWARE_FILENAME="${BASE_FILENAME}.fw"
FIRMWARE_FILE="${GLB_ARTEFACTS_DIR}/${FIRMWARE_FILENAME}"
IMAGE_BASE_FILENAME="${BASE_FILENAME}"
IMAGE_BASE_FILE="${GLB_ARTEFACTS_DIR}/${IMAGE_BASE_FILENAME}"
IMAGE_FILE_EXTENSION=".img"

# Consolidated priority file across all projects + firmware
SQUASHFS_PRIORITIES_FILE="$FIRMWARE_DIR/squashfs.priority"
rm -f "$SQUASHFS_PRIORITIES_FILE"
PRIO_TEMP="$FIRMWARE_DIR/.priorities.tmp"
PRIO_PATHS="$FIRMWARE_DIR/.prio.paths"
rm -f "$PRIO_TEMP" "$PRIO_PATHS"

: > "$PRIO_PATHS"
for idx in "${!PROJECT_DIRS[@]}"; do
    prio_file="${PROJECT_DIRS[$idx]}/ALLOY-FS-PRIORITIES"
    if [[ -f "$prio_file" ]]; then
        while read -r path weight; do
            [[ -z "$path" ]] && continue
            if ! grep -qx -- "$path" "$PRIO_PATHS" 2>/dev/null; then
                echo "$path" >> "$PRIO_PATHS"
                echo "$path $weight" >> "$PRIO_TEMP"
            fi
        done < "$prio_file"
    fi
done

for ((i = 0; i < ${#SQUASHFS_PRIORITIES[@]}; i += 2 )); do
    p="${SQUASHFS_PRIORITIES[i]}"
    w="${SQUASHFS_PRIORITIES[i + 1]}"
    if ! grep -qx -- "$p" "$PRIO_PATHS" 2>/dev/null; then
        echo "$p $w" >> "$PRIO_TEMP"
    fi
done

if [[ -s "$PRIO_TEMP" ]]; then
    sort -k2,2nr -o "$SQUASHFS_PRIORITIES_FILE" "$PRIO_TEMP"
else
    : > "$SQUASHFS_PRIORITIES_FILE"
fi
rm -f "$PRIO_TEMP" "$PRIO_PATHS"

# FILESYSTEM OVERLAY PREPARATION
# Create per-node release directories under /srv/alloy and an init symlink
echo "Packaging project releases..."

OVERLAY_ROOT="${FIRMWARE_DIR}/rootfs_overlay/srv"
rm -rf "$OVERLAY_ROOT"
mkdir -p "$OVERLAY_ROOT/alloy"

for i in "${!RELEASE_DIRS[@]}"; do
    node_dir="${OVERLAY_ROOT}/alloy/${PROJECT_NAMES[$i]}"
    if [[ -e "$node_dir" ]]; then
        error 1 "Destination already exists: ${node_dir}"
    fi
    mkdir -p "$node_dir"
    cp -R "${RELEASE_DIRS[$i]}/." "$node_dir"
    "${GLB_COMMON_SYSTEM_DIR}/scripts/scrub-otp-release.sh" "$node_dir"
done

# If an overlay directory is provided, merge it into the rootfs_overlay now
if [[ -n "$OVERLAY_DIR" ]]; then
    rsync -a "$OVERLAY_DIR/" "${FIRMWARE_DIR}/rootfs_overlay/"
fi

# Create init symlink to first node's directory
ln -sfn "${PROJECT_ROOTS[0]}" "${OVERLAY_ROOT}/erlang"

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
{
    echo "{";
    echo "    \"architecture\": \"${CROSSCOMPILE_ARCH}\",";
    echo "    \"serial\": \"${ARG_SERIAL}\",";
    echo "    \"target\": \"${GLB_TARGET_NAME}\",";
    echo "    \"system_common_version\": \"${GLB_COMMON_SYSTEM_VER}\",";
    echo "    \"system_common_vcs\": \"${GLB_VCS_TAG}\",";
    echo "    \"system_target_version\": \"${GLB_TARGET_SYSTEM_VER}\",";
    echo "    \"system_target_vcs\": \"${GLB_VCS_TAG}\",";
    echo "    \"projects\": {";
    for pi in "${!APP_NAMES[@]}"; do
        echo "        \"${APP_NAMES[$pi]}\": {";
        echo "            \"root\": \"${PROJECT_ROOTS[$pi]}\",";
        echo "            \"app_ver\": \"${APP_VERS[$pi]}\",";
        echo "            \"rel_ver\": \"${REL_VERS[$pi]}\",";
        echo "            \"type\": \"${PROJ_TYPES[$pi]}\",";
        echo "            \"profile\": \"${PROJ_PROFILES[$pi]}\",";
        echo "            \"erts_ver\": \"${ERTS_VERS[$pi]}\",";
        echo "            \"vcs\": \"${PROJ_VCS_TAGS[$pi]}\"";
        echo -n "        }";
        if [[ $pi -lt $((${#APP_NAMES[@]}-1)) ]]; then echo ","; else echo; fi
    done
    echo "    }";
    echo "}";
} > "$ALLOY_FIRMWARE_FILE"

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
