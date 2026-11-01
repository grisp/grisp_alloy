#!/usr/bin/env bash

# build-project.sh - GRiSP Alloy Project Builder
#
# This script builds a project release for a target and packages it as a
# self-contained artefact for later firmware assembly.
#
# HIGH-LEVEL FLOW:
# 1. Parse arguments and validate inputs
# 2. Handle Vagrant VM execution on non-Linux hosts or when forced
# 3. Ensure SDK is installed
# 4. Load project plugins and detect project type
# 5. Build the project release for the specified profile
# 6. Create project artefact tarball with:
#    - ALLOY-PROJECT (manifest)
#    - ALLOY-FS-PRIORITIES (optional, may be empty)
#    - release/ (OTP release directory)

set -e

ARGS=( "$@" )

show_usage()
{
    echo "USAGE: build-project.sh OPTIONS TARGET PROJECT_DIR"
    echo "OPTIONS:"
    echo " -h | --help"
    echo "    Show this"
    echo " -d | --debug"
    echo "    Print scripts debug information"
    echo " -c | --clean"
    echo "    Cleanup the curent state and start from scratch"
    echo " -V | --force-vagrant"
    echo "    Using the Vagrant VM even on Linux"
    echo " -P | --provision"
    echo "    Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K | --keep-vagrant"
    echo "    Keep the vagrant VM running after exiting"
    echo " -p | --profile <PROFILE>"
    echo "    Project profile to build (default: default)"
    echo " --sdk-lang <LANGUAGE>"
    echo "    Require an additional SDK language (repeatable; project language is detected)."
    echo " --external <DIR>"
    echo "    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs."
    echo
    echo "e.g. build-project.sh grisp2 ~/my_project"
}

# Parse script's arguments (GNU-like long/short options)
source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 0
args_add c clean ARG_CLEAN flag true false
args_add V force-vagrant ARG_FORCE_VAGRANT flag true false
args_add P provision ARG_PROVISION_VAGRANT flag true false
args_add K keep-vagrant ARG_KEEP_VAGRANT flag true false
args_add p profile ARG_PROJECT_PROFILE value "default"
args_add "" external ARG_EXTERNAL_DIRS accum
args_add "" sdk-lang ARG_SDK_LANGS accum

if ! args_parse "$@"; then
    exit 1
fi
if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi
# Positional TARGET PROJECT_DIR
POSITIONALS=( "${POSITIONAL[@]}" )
if [[ ${#POSITIONALS[@]} -lt 2 ]]; then
    echo "ERROR: Missing target or project directory"
    show_usage
    exit 1
fi
ARG_TARGET="${POSITIONALS[0]}"
ARG_PROJECT="${POSITIONALS[1]}"
if [[ ${#POSITIONALS[@]} -gt 2 ]]; then
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
    error 1 "cannot find project $ARG_PROJECT"
fi

SOURCE_PROJECT_DIR="$( cd "$ARG_PROJECT"; pwd )"
PROJECT_NAME="$( basename "$SOURCE_PROJECT_DIR" )"
VCS_TAG_FILE=".alloy_vcs_tag"
PROJECT_EXCLUDE_FILE=".grisp_alloy_exclude"
RSYNC_CMD=( rsync -aqH --copy-links --delete --exclude='_build/' --exclude='target/' --exclude='*.beam' \
            --exclude='*.o' --exclude='*.so' )
if [[ -f "$SOURCE_PROJECT_DIR/$PROJECT_EXCLUDE_FILE" ]]; then
    RSYNC_CMD+=( --exclude-from="$SOURCE_PROJECT_DIR/$PROJECT_EXCLUDE_FILE" )
fi

set_debug_level "$ARG_DEBUG"

# VAGRANT VM EXECUTION BLOCK
# Non-Linux hosts (macOS, etc.) or forced Vagrant mode require VM execution
# This entire block sets up VM, syncs project files, and re-executes script inside VM
if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    VAGRANT_PROJECT_BUILD_DIR="${GLB_VAGRANT_PROJECT_BUILD_DIR}/source/${PROJECT_NAME}"
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    vagrant exec rm -rf "$VAGRANT_PROJECT_BUILD_DIR"
    vagrant exec mkdir -p "$VAGRANT_PROJECT_BUILD_DIR"
    vagrant ssh-config > .vagrant.ssh_config

    "${RSYNC_CMD[@]}" -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" \
        "$SOURCE_PROJECT_DIR"/. "vagrant@default:${VAGRANT_PROJECT_BUILD_DIR}"

    # Keep track of the project VCS tag
    if [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
        PROJECT_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -D -c "$SOURCE_PROJECT_DIR" )"
        echo "$PROJECT_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${VAGRANT_PROJECT_BUILD_DIR}/${VCS_TAG_FILE}"
    fi

    # Keep track of the alloy VCS tag
    if [[ -d "$GLB_TOP_DIR/.git" ]]; then
        GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -D -c "$GLB_TOP_DIR" )"
        echo "$GLB_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${GLB_VAGRANT_TOP_DIR}/${VCS_TAG_FILE}"
    fi

    NEW_ARGS=( )
    # Resolve installed SDKs in the Linux guest, where their tools run.
    for sdk_language in "${ARG_SDK_LANGS[@]}"; do
        NEW_ARGS+=( "--sdk-lang" "$sdk_language" )
    done
    if [[ ${ARG_DEBUG_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--debug" )
    fi
    if [[ ${ARG_CLEAN_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--clean" )
    fi
    if [[ ${ARG_PROJECT_PROFILE_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--profile" "$ARG_PROJECT_PROFILE" )
    fi
    VAGRANT_EXTERNAL_DIRS=( )
    alloy_vagrant_sync_external_roots VAGRANT_EXTERNAL_DIRS
    for external_dir in "${VAGRANT_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
    done
    NEW_ARGS+=( "$ARG_TARGET" )
    NEW_ARGS+=( "$VAGRANT_PROJECT_BUILD_DIR" )

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec -- "${GLB_VAGRANT_TOP_DIR}/build-project.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE

# PROJECT MANAGMENT PLUGIN: Loads and sets up project management plugins
source "${GLB_SCRIPT_DIR}/plugins/project.sh"
project_setup
project_detect PROJECT_TYPE "$SOURCE_PROJECT_DIR"

# Project requirements add to explicit --sdk-lang requirements. An SDK may
# supply additional languages, but there must be exactly one matching build.
project_require_sdk

# SDK INSTALLATION
install_sdk

source "$GLB_SCRIPT_DIR/project-artifacts.sh"

# PROJECT BUILD PREPARATION
PROJECT_DIR="${GLB_PROJECT_BUILD_DIR}/${GLB_TARGET_NAME}/${SDK_LANGUAGE_SET}/builds/${PROJECT_NAME}"
PACKAGE_DIR="${GLB_PROJECT_BUILD_DIR}/${GLB_TARGET_NAME}/${SDK_LANGUAGE_SET}/packages/${PROJECT_NAME}"
GLB_VCS_TAG="unknown"
if [[ -d "${GLB_TOP_DIR}/.git" ]]; then
    GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -D -c "$GLB_TOP_DIR" )"
elif [[ -f "${GLB_TOP_DIR}/${VCS_TAG_FILE}" ]]; then
    GLB_VCS_TAG="$( cat "${GLB_TOP_DIR}/${VCS_TAG_FILE}" )"
fi

# Clean previous builds if requested
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$PROJECT_DIR"
    rm -rf "$PACKAGE_DIR"
fi


# Copy source project to build directory and prepare for compilation
echo "Building $PROJECT_TYPE project..."
mkdir -p "$PROJECT_DIR"
printf '%q ' "${RSYNC_CMD[@]}" "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
printf '\n'
"${RSYNC_CMD[@]}" "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/${VCS_TAG_FILE}" ]] \
        && [[ -d "$PROJECT_DIR/.git" ]]; then
    "${GLB_SCRIPT_DIR}/git-info.sh" -c "$PROJECT_DIR" \
        -o "$PROJECT_DIR/${VCS_TAG_FILE}"
fi
mkdir -p "$PACKAGE_DIR"

# PROJECT COMPILATION
cd "$PROJECT_DIR"
PROJECT_VCS_TAG="unknown"
if [[ -f "$VCS_TAG_FILE" ]]; then
    PROJECT_VCS_TAG="$( cat "$VCS_TAG_FILE" )"
fi
# Bind the selected SDK/C baseline; each plugin requests its language environment.
source "${GLB_SCRIPT_DIR}/cross-env.sh" "$GLB_TARGET_NAME"
rm -rf "_build/"

# build project using plugin
project_build RELEASE_DIR "$PROJECT_DIR" "$ARG_PROJECT_PROFILE" "$GRISP_SDK_SYSROOT/usr/lib/erlang"
if [[ ! -d "$RELEASE_DIR" ]]; then
    error 1 "Failed to build $PROJECT_TYPE project in $RELEASE_DIR"
fi
APP_NAME=""
APP_VER=""
RELEASE_NAME=""
RELEASE_VERSION=""
project_metadata APP_NAME APP_VER RELEASE_NAME RELEASE_VERSION "$RELEASE_DIR" "$PROJECT_DIR"

TARBALL_BASENAME="$(project_archive_basename \
    "$RELEASE_NAME" "$RELEASE_VERSION" "$GLB_TARGET_NAME" "$ARG_PROJECT_PROFILE")"
TARBALL_FILE="${GLB_ARTEFACTS_DIR}/${TARBALL_BASENAME}.tgz"

###############################################################################
# Release validations
###############################################################################

PROJECT_APP_NAME="$APP_NAME"
PROJECT_APP_VERSION="$APP_VER"
PROJECT_RELEASE_NAME="$RELEASE_NAME"
PROJECT_RELEASE_VERSION="$RELEASE_VERSION"
PROJECT_MANIFEST_VERSION=2
# Compatibility with SDK common-system 0.2.0; remove when support ends.
[[ ${SDK_COMPAT_V020:-false} != true ]] || PROJECT_MANIFEST_VERSION=1
PROJECT_SDK_BUILD_ID="$SDK_BUILD_ID"
project_runtime PROJECT_RUNTIME PROJECT_ENTRYPOINT "$RELEASE_DIR" "$PROJECT_DIR"
project_manifest_normalize
project_validate_payload "$RELEASE_DIR"
RELEASE_ERTS_VERSION="$PROJECT_ERTS_VERSION"

rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR/release"
cp -R "$RELEASE_DIR"/. "$PACKAGE_DIR/release/"

# Emit ALLOY-PROJECT manifest (bash-friendly)
MANIFEST_FILE="$PACKAGE_DIR/ALLOY-PROJECT"
{
    printf 'PROJECT_MANIFEST_VERSION=%s\n' "$PROJECT_MANIFEST_VERSION"
    printf 'PROJECT_RUNTIME=%q\n' "$PROJECT_RUNTIME"
    printf 'PROJECT_ENTRYPOINT=%q\n' "$PROJECT_ENTRYPOINT"
    printf 'PROJECT_SDK_BUILD_ID=%q\n' "$SDK_BUILD_ID"
    printf 'PROJECT_SDK_LANGUAGE_SET=%q\n' "$SDK_LANGUAGE_SET"
    printf 'PROJECT_BUILD_PROFILE=%q\n' "${PROJECT_BUILD_PROFILE:-$ARG_PROJECT_PROFILE}"
    if [[ $PROJECT_TYPE == rust ]]; then
        printf 'PROJECT_RUST_TARGET=%q\n' "$SDK_RUST_TARGET"
        printf 'PROJECT_RUST_VERSION=%q\n' "$SDK_RUST_VERSION"
        printf 'PROJECT_CARGO_VERSION=%q\n' "$SDK_CARGO_VERSION"
    fi
    printf 'PROJECT_APP_NAME=%q\n' "${APP_NAME}"
    printf 'PROJECT_APP_VERSION=%q\n' "${APP_VER}"
    printf 'PROJECT_TYPE=%q\n' "${PROJECT_TYPE}"
    printf 'PROJECT_PROFILE=%q\n' "${ARG_PROJECT_PROFILE}"
    printf 'PROJECT_TARGET_NAME=%q\n' "${GLB_TARGET_NAME}"
    printf 'PROJECT_COMMON_SYSTEM_VER=%q\n' "${GLB_COMMON_SYSTEM_VER}"
    printf 'PROJECT_TARGET_SYSTEM_VER=%q\n' "${GLB_TARGET_SYSTEM_VER}"
    printf 'PROJECT_TARGET_SYSTEM_SOURCE=%q\n' "${GLB_TARGET_SYSTEM_SOURCE}"
    printf 'PROJECT_COMMON_SYSTEM_TREE_SHA256=%q\n' "${GLB_COMMON_SYSTEM_TREE_SHA256}"
    printf 'PROJECT_TARGET_SYSTEM_TREE_SHA256=%q\n' "${GLB_TARGET_SYSTEM_TREE_SHA256}"
    printf 'PROJECT_CROSSCOMPILE_ARCH=%q\n' "${CROSSCOMPILE_ARCH}"
    printf 'PROJECT_ERTS_VERSION=%q\n' "${RELEASE_ERTS_VERSION}"
    printf 'PROJECT_RELEASE_NAME=%q\n' "${RELEASE_NAME}"
    printf 'PROJECT_RELEASE_VERSION=%q\n' "${RELEASE_VERSION}"
    printf 'PROJECT_VCS_PROJECT=%q\n' "${PROJECT_VCS_TAG}"
    printf 'PROJECT_VCS_ALLOY=%q\n' "${GLB_VCS_TAG}"
} > "$MANIFEST_FILE"

# Emit ALLOY-FS-PRIORITIES (empty for now)
touch "$PACKAGE_DIR/ALLOY-FS-PRIORITIES"

# Create tarball
mkdir -p "$( dirname "$TARBALL_FILE" )"
tar -C "$PACKAGE_DIR" -czf "$TARBALL_FILE" .

echo "Project artefact created: $( basename "$TARBALL_FILE" )"

echo "Done"

exit 0
