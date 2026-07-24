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
    echo " --external <DIR>"
    echo "    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs."
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
args_add "" external ARG_EXTERNAL_DIRS accum

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
# shellcheck source=scripts/sdk-artifacts.sh
source "$GLB_SCRIPT_DIR/sdk-artifacts.sh"
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
    VAGRANT_EXTERNAL_DIRS=( )
    alloy_vagrant_sync_external_roots VAGRANT_EXTERNAL_DIRS
    for external_dir in "${VAGRANT_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
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

sdk_artifacts_init_defaults
FIRMWARE_DEFAULT_PROFILE=default
CRUCIBLE_FILE="${GLB_TARGET_SYSTEM_DIR}/crucible.sh"
if [[ -f "$CRUCIBLE_FILE" ]]; then
    source "$CRUCIBLE_FILE"
fi
sdk_validate_artifact_config

BUILDROOT_BASE_PROFILE=""
if sdk_artifacts_enabled && sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
    BUILDROOT_BASE_PROFILE="$(sdk_single_rootfs_source_profile)"
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
    GRISP_ALLOY_EXTERNAL_PATH="$GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE" \
    GRISP_BUILD_HOST_ARCH="$HOST_ARCH" \
    GLB_DEBUG="$GLB_DEBUG"
    # BR2_INSTRUMENTATION_SCRIPTS="$GLB_COMMON_SYSTEM_DIR/scripts/debug.sh"
)

if [[ $ARG_DEBUG -gt 0 ]]; then
    BUILDROOT_MAKE_PARAMS=( ${BUILDROOT_MAKE_PARAMS[@]} "V=1" )
fi

if [[ $ARG_BRCMD == "true" ]]; then
    echo "Buildroot command:"
    printf 'make'
    printf ' %q' "${BUILDROOT_MAKE_PARAMS[@]}"
    printf '\n'
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

# BUILD STEP FUNCTIONS
# These functions are executed using the checkpoint system to allow resuming builds

array_contains_value() {
    local needle="$1"
    shift
    local value

    for value in "$@"; do
        if [[ "$value" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

append_unique() {
    local var="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        return 0
    fi
    if ! eval "array_contains_value \"\$value\" \"\${${var}[@]}\""; then
        eval "${var}+=(\"\$value\")"
    fi
}

artifact_clean_packages() {
    local artifact="$1"
    local key
    local var

    key="$(sdk_artifact_key "$artifact")"
    var="SDK_ARTIFACT_CLEAN_PACKAGES_${key}"
    eval 'printf "%s\n" "${'"$var"'[@]}"'
}

clean_buildroot_packages() {
    local p

    for p in "$@"; do
        [[ -n "$p" ]] || continue
        echo rm -rf "${BUILD_DIR}/build/${p}"*
        rm -rf "${BUILD_DIR}/build/${p}"*
    done
}

profile_artifact_clean_package_union() {
    local artifact
    local package
    local packages=( )

    for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
        while IFS= read -r package; do
            append_unique packages "$package"
        done < <(artifact_clean_packages "$artifact")
    done

    printf '%s\n' "${packages[@]}"
}

clean_initial_packages() {
    local profile_packages=( )
    local initial_packages=( )
    local p

    if sdk_artifacts_enabled; then
        while IFS= read -r p; do
            append_unique profile_packages "$p"
        done < <(profile_artifact_clean_package_union)

        for p in "${ARG_CLEAN_PACKAGES[@]}"; do
            if array_contains_value "$p" "${profile_packages[@]}"; then
                continue
            fi
            append_unique initial_packages "$p"
        done
    else
        for p in "${ARG_CLEAN_PACKAGES[@]}"; do
            append_unique initial_packages "$p"
        done
    fi

    clean_buildroot_packages "${initial_packages[@]}"
}

prepare_environment()
{
    echo "Preparing environment..."
    if [[ $USER == "" ]]; then
        error 1 "USER environment variable is not set"
    fi
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
    local profile="${1:-}"
    local effective_profile="$profile"
    local profile_key
    local profile_var
    local profile_lines=( )

    if [[ -z "$effective_profile" && -n "${BUILDROOT_BASE_PROFILE:-}" ]]; then
        effective_profile="$BUILDROOT_BASE_PROFILE"
    fi

    # Merge common and target-specific buildroot configurations
    cat > "$FINAL_DEFCONFIG" << EOF
########## GENERATED BY BUILDING SCRIPT
BR2_HOST_DIR="${GLB_SDK_HOST_DIR}"

########## FROM COMMON SYSTEM ${GLB_COMMON_SYSTEM_VER}
$( cat "$COMMON_SYSTEM_DEFCONFIG" )

########## FROM ${GLB_TARGET_NAME} TARGET SYSTEM ${GLB_TARGET_SYSTEM_VER}
$( cat "$TARGET_SYSTEM_DEFCONFIG" )
EOF

    if [[ -n "$effective_profile" ]]; then
        profile_key="$(sdk_artifact_key "$effective_profile")"
        profile_var="SDK_PROFILE_DEFCONFIG_${profile_key}"
        eval 'profile_lines=( "${'"$profile_var"'[@]}" )'
        {
            echo
            echo "########## SDK ARTIFACT PROFILE ${effective_profile}"
            printf '%s\n' "${profile_lines[@]}"
        } >> "$FINAL_DEFCONFIG"
    fi

    # Generate final buildroot .config from merged defconfig
    if [[ -n "$profile" ]]; then
        echo "Configuring buildroot for $GLB_TARGET_NAME SDK artifact profile $profile..."
    elif [[ -n "$effective_profile" ]]; then
        echo "Configuring buildroot for $GLB_TARGET_NAME single-rootfs source profile $effective_profile..."
    else
        echo "Configuring buildroot for $GLB_TARGET_NAME..."
    fi
    make "${BUILDROOT_MAKE_PARAMS[@]}" defconfig
}

run_buildroot()
{
    # Execute main buildroot build (cross-compile all packages)
    local profile="${1:-}"

    if [[ -n "$profile" ]]; then
        echo "Run buildroot for $GLB_TARGET_NAME SDK artifact profile $profile..."
    elif [[ -n "${BUILDROOT_BASE_PROFILE:-}" ]]; then
        echo "Run buildroot for $GLB_TARGET_NAME single-rootfs source profile $BUILDROOT_BASE_PROFILE..."
    else
        echo "Run buildroot for $GLB_TARGET_NAME..."
    fi
    make "${BUILDROOT_MAKE_PARAMS[@]}"
}

run_sdk_artifact_profile_hook() {
    local profile="$1"

    if declare -F sdk_artifact_profile_post_build >/dev/null; then
        sdk_artifact_profile_post_build "$profile"
    fi
}

artifact_clean_intersects_user_clean() {
    local artifact="$1"
    local package

    while IFS= read -r package; do
        if array_contains_value "$package" "${ARG_CLEAN_PACKAGES[@]}"; then
            return 0
        fi
    done < <(artifact_clean_packages "$artifact")

    return 1
}

add_artifact_clean_packages() {
    local cleanup_var="$1"
    local artifact="$2"
    local package

    while IFS= read -r package; do
        append_unique "$cleanup_var" "$package"
    done < <(artifact_clean_packages "$artifact")
}

sdk_invariant_artifacts() {
    local artifacts=( )
    local artifact

    if sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
        append_unique artifacts "rootfs.squashfs"
    fi
    for artifact in "${SDK_INVARIANT_ARTIFACTS[@]}"; do
        append_unique artifacts "$artifact"
    done

    printf '%s\n' "${artifacts[@]}"
}

sdk_invariant_fingerprint_artifact() {
    local artifact="$1"

    if [[ "$artifact" == "rootfs.squashfs" && -f "${BUILD_DIR}/images/rootfs.tar" ]]; then
        printf '%s\n' "rootfs.tar"
    else
        printf '%s\n' "$artifact"
    fi
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

sha256_rootfs_tar() {
    local tar_path="$1"

    if [[ ${#SDK_SINGLE_ROOTFS_IGNORE_PATHS[@]} -eq 0 ]]; then
        sha256_file "$tar_path"
        return 0
    fi

    python3 - "$tar_path" "${SDK_SINGLE_ROOTFS_IGNORE_PATHS[@]}" <<'PY'
import hashlib
import sys
import tarfile
from pathlib import Path

tar_path = Path(sys.argv[1])
ignored = [p.strip("/").removeprefix("./").rstrip("/") for p in sys.argv[2:]]
ignored = [p for p in ignored if p]
digest = hashlib.sha256()


def is_ignored(name: str) -> bool:
    normalized = name.strip("/").removeprefix("./").rstrip("/")
    return any(normalized == prefix or normalized.startswith(prefix + "/") for prefix in ignored)


with tarfile.open(tar_path, "r") as archive:
    for member in archive:
        if is_ignored(member.name):
            continue
        fields = [
            member.name,
            member.type.decode("latin1") if isinstance(member.type, bytes) else str(member.type),
            str(member.mode),
            str(member.uid),
            str(member.gid),
            str(member.size),
            member.linkname,
        ]
        digest.update("\0".join(fields).encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        if member.isfile():
            fileobj = archive.extractfile(member)
            if fileobj is None:
                raise SystemExit(f"ERROR: failed to read tar member {member.name}")
            while True:
                chunk = fileobj.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
            digest.update(b"\0")

print(digest.hexdigest())
PY
}

sha256_invariant_fingerprint() {
    local artifact="$1"
    local path="$2"

    if [[ "$artifact" == "rootfs.squashfs" && "$(basename "$path")" == "rootfs.tar" ]]; then
        sha256_rootfs_tar "$path"
    else
        sha256_file "$path"
    fi
}

capture_invariant_hashes() {
    local names_var="$1"
    local hashes_var="$2"
    local fingerprints_var="$3"
    local backups_var="$4"
    local fingerprint_backups_var="$5"
    local backup_dir="$6"
    local artifact
    local path
    local fingerprint
    local fingerprint_path
    local hash
    local backup_path
    local fingerprint_backup_path

    while IFS= read -r artifact; do
        [[ -n "$artifact" ]] || continue
        sdk_validate_artifact_name "$artifact"
        path="${BUILD_DIR}/images/${artifact}"
        if [[ ! -f "$path" ]]; then
            error 1 "SDK invariant artifact missing after baseline build: ${artifact}"
        fi
        fingerprint="$(sdk_invariant_fingerprint_artifact "$artifact")"
        fingerprint_path="${BUILD_DIR}/images/${fingerprint}"
        if [[ ! -f "$fingerprint_path" ]]; then
            error 1 "SDK invariant fingerprint artifact missing after baseline build: ${fingerprint}"
        fi
        hash="$(sha256_invariant_fingerprint "$artifact" "$fingerprint_path")"
        backup_path="${backup_dir}/${artifact}"
        fingerprint_backup_path="${backup_dir}/${fingerprint}"
        cp -f "$path" "$backup_path"
        if [[ "$fingerprint" != "$artifact" ]]; then
            cp -f "$fingerprint_path" "$fingerprint_backup_path"
        fi
        eval "${names_var}+=(\"\$artifact\")"
        eval "${hashes_var}+=(\"\$hash\")"
        eval "${fingerprints_var}+=(\"\$fingerprint\")"
        eval "${backups_var}+=(\"\$backup_path\")"
        eval "${fingerprint_backups_var}+=(\"\$fingerprint_backup_path\")"
    done < <(sdk_invariant_artifacts)
}

validate_invariant_hashes() {
    local names_var="$1"
    local hashes_var="$2"
    local fingerprints_var="$3"
    local backups_var="$4"
    local fingerprint_backups_var="$5"
    local profile="$6"
    local restore_rootfs="${7:-true}"
    local count
    local i
    local artifact
    local fingerprint
    local expected
    local actual
    local path
    local fingerprint_path
    local backup_path
    local fingerprint_backup_path

    eval "count=\${#${names_var}[@]}"
    for ((i = 0; i < count; i += 1)); do
        eval "artifact=\${${names_var}[$i]}"
        eval "expected=\${${hashes_var}[$i]}"
        eval "fingerprint=\${${fingerprints_var}[$i]}"
        eval "backup_path=\${${backups_var}[$i]}"
        eval "fingerprint_backup_path=\${${fingerprint_backups_var}[$i]}"
        path="${BUILD_DIR}/images/${artifact}"
        fingerprint_path="${BUILD_DIR}/images/${fingerprint}"
        if [[ ! -f "$path" ]]; then
            error 1 "SDK artifact profile ${profile} removed invariant artifact: ${artifact}"
        fi
        if [[ ! -f "$fingerprint_path" ]]; then
            error 1 "SDK artifact profile ${profile} removed invariant fingerprint artifact: ${fingerprint}"
        fi
        actual="$(sha256_invariant_fingerprint "$artifact" "$fingerprint_path")"
        if [[ "$actual" != "$expected" ]]; then
            error 1 "SDK artifact profile ${profile} changed invariant artifact ${artifact}; declare it profile-driven or keep it common"
        fi
        if [[ "$restore_rootfs" == true && "$artifact" == "rootfs.squashfs" && "$fingerprint" != "$artifact" &&
            -f "$backup_path" ]]; then
            if ! cmp -s "$path" "$backup_path"; then
                echo "Restoring invariant artifact ${artifact} from baseline after profile ${profile}..."
                cp -f "$backup_path" "$path"
            fi
            if [[ -f "$fingerprint_backup_path" ]] && ! cmp -s "$fingerprint_path" "$fingerprint_backup_path"; then
                echo "Restoring invariant fingerprint artifact ${fingerprint} from baseline after profile ${profile}..."
                cp -f "$fingerprint_backup_path" "$fingerprint_path"
            fi
        fi
    done
}

write_sdk_artifact_metadata() {
    local default_profile="$1"
    local invariant_names_var="$2"
    local invariant_hashes_var="$3"
    local invariant_fingerprints_var="$4"
    local metadata="${BUILD_DIR}/images/sdk-artifact-profiles.env"
    local i
    local count
    local artifact
    local fingerprint
    local hash
    local line

    {
        echo "# Generated by build-sdk.sh"
        echo "SDK_ARTIFACT_PROFILES=\"${SDK_ARTIFACT_PROFILES[*]}\""
        echo "SDK_PROFILE_ARTIFACTS=\"${SDK_PROFILE_ARTIFACTS[*]}\""
        echo "SDK_DEFAULT_ARTIFACT_PROFILE=\"${default_profile}\""
        echo "SDK_SINGLE_ROOTFS=\"${SDK_SINGLE_ROOTFS}\""
        if sdk_artifacts_enabled && sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
            echo "SDK_SINGLE_ROOTFS_SOURCE_PROFILE=\"$(sdk_single_rootfs_source_profile)\""
        fi
        eval "count=\${#${invariant_names_var}[@]}"
        for ((i = 0; i < count; i += 1)); do
            eval "artifact=\${${invariant_names_var}[$i]}"
            eval "hash=\${${invariant_hashes_var}[$i]}"
            eval "fingerprint=\${${invariant_fingerprints_var}[$i]}"
            echo "SDK_INVARIANT_SHA256_${artifact//[^A-Za-z0-9_]/_}=\"${hash}\""
            echo "SDK_INVARIANT_FINGERPRINT_${artifact//[^A-Za-z0-9_]/_}=\"${fingerprint}\""
        done
        for line in "${SDK_PROFILE_METADATA_LINES[@]}"; do
            echo "$line"
        done
    } > "$metadata"
}

run_sdk_artifact_profiles() {
    local invariant_names=( )
    local invariant_hashes=( )
    local invariant_fingerprints=( )
    local invariant_backups=( )
    local invariant_fingerprint_backups=( )
    local invariant_backup_dir="${BUILD_DIR}/.sdk-invariant-baseline"
    local profile
    local artifact
    local suffix_path
    local unsuffixed_path
    local pass_needed
    local cleanup
    local package
    local generated
    local reused
    local default_profile
    local rootfs_source_profile
    local profile_key
    local status
    local restore_rootfs

    if ! sdk_artifacts_enabled; then
        rm -f "${BUILD_DIR}/images/sdk-artifact-profiles.env"
        return 0
    fi

    SDK_PROFILE_METADATA_LINES=( )
    mkdir -p "${BUILD_DIR}/images"
    rm -rf "$invariant_backup_dir"
    mkdir -p "$invariant_backup_dir"
    capture_invariant_hashes invariant_names invariant_hashes invariant_fingerprints invariant_backups invariant_fingerprint_backups "$invariant_backup_dir"
    rootfs_source_profile=""
    if sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
        rootfs_source_profile="$(sdk_single_rootfs_source_profile)"
    fi

    for profile in "${SDK_ARTIFACT_PROFILES[@]}"; do
        profile_key="$(sdk_artifact_key "$profile")"
        pass_needed=false
        cleanup=( )
        generated=( )
        reused=( )
        status=reused

        for package in "${ARG_CLEAN_PACKAGES[@]}"; do
            append_unique cleanup "$package"
        done

        for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
            unsuffixed_path="${BUILD_DIR}/images/${artifact}"
            suffix_path="${unsuffixed_path}.${profile}"

            if [[ ! -f "$suffix_path" ]]; then
                pass_needed=true
                add_artifact_clean_packages cleanup "$artifact"
            elif artifact_clean_intersects_user_clean "$artifact"; then
                pass_needed=true
                add_artifact_clean_packages cleanup "$artifact"
            fi
        done

        if [[ "$pass_needed" == true ]]; then
            status=built
            prepare_buildroot "$profile"
            clean_buildroot_packages "${cleanup[@]}"

            for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
                rm -f "${BUILD_DIR}/images/${artifact}"
            done

            run_buildroot "$profile"
            run_sdk_artifact_profile_hook "$profile"
            restore_rootfs=true
            if [[ -n "$rootfs_source_profile" && "$profile" == "$rootfs_source_profile" ]]; then
                restore_rootfs=false
            fi
            validate_invariant_hashes invariant_names invariant_hashes invariant_fingerprints invariant_backups invariant_fingerprint_backups "$profile" "$restore_rootfs"

            for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
                unsuffixed_path="${BUILD_DIR}/images/${artifact}"
                suffix_path="${unsuffixed_path}.${profile}"
                if [[ -f "$unsuffixed_path" ]]; then
                    mv -f "$unsuffixed_path" "$suffix_path"
                    generated+=( "$artifact" )
                elif [[ -f "$suffix_path" ]]; then
                    reused+=( "$artifact" )
                else
                    error 1 "SDK artifact profile ${profile} did not produce required artifact ${artifact}"
                fi
            done
        else
            for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
                reused+=( "$artifact" )
            done
        fi

        echo "SDK artifact profile ${profile}: generated [${generated[*]}], reused [${reused[*]}]"
        SDK_PROFILE_METADATA_LINES+=( "SDK_PROFILE_${profile_key}_STATUS=\"${status}\"" )
        SDK_PROFILE_METADATA_LINES+=( "SDK_PROFILE_${profile_key}_CLEAN_PACKAGES=\"${cleanup[*]}\"" )
        SDK_PROFILE_METADATA_LINES+=( "SDK_PROFILE_${profile_key}_GENERATED=\"${generated[*]}\"" )
        SDK_PROFILE_METADATA_LINES+=( "SDK_PROFILE_${profile_key}_REUSED=\"${reused[*]}\"" )
    done

    default_profile="$(sdk_default_artifact_profile)"
    for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
        suffix_path="${BUILD_DIR}/images/${artifact}.${default_profile}"
        if [[ ! -f "$suffix_path" ]]; then
            error 1 "Default SDK artifact missing: ${artifact}.${default_profile}"
        fi
        ln -sfn "${artifact}.${default_profile}" "${BUILD_DIR}/images/${artifact}"
    done

    write_sdk_artifact_metadata "$default_profile" invariant_names invariant_hashes invariant_fingerprints
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
clean_initial_packages
checkpoint prepare_buildroot "$CHECKPOINTS_DIR"
checkpoint run_buildroot "$CHECKPOINTS_DIR"
run_sdk_artifact_profiles
make_sdk

echo "Done"
