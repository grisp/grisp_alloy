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
    echo "USAGE: build-project.sh [-h] [-d] [-c] [-V] [-P] [-K] TARGET PROJECT_DIR [PROFILE]"
    echo "OPTIONS:"
    echo " -h Show this"
    echo " -d Print scripts debug information"
    echo " -c Cleanup the curent state and start from scratch"
    echo " -V Using the Vagrant VM even on Linux"
    echo " -P Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K Keep the vagrant VM running after exiting"
    echo
    echo "e.g. build-project.sh grisp2 ~/my_project"
}

# Parse script's arguments
OPTIND=1
ARG_DEBUG="${DEBUG:-0}"
ARG_CLEAN=false
ARG_PROJECT_PROFILE="default"
ARG_FORCE_VAGRANT=false
ARG_KEEP_VAGRANT=false
while getopts "hdcstVPK" opt; do
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
    echo "ERROR: Missing target name"
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
fi
if [[ $# > 0 ]]; then
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
    error 1 "cannot find Erlang project $ARG_PROJECT"
fi

SOURCE_PROJECT_DIR="$( cd $ARG_PROJECT; pwd )"
PROJECT_NAME="$( basename "$SOURCE_PROJECT_DIR" )"
VCS_TAG_FILE=".alloy_vcs_tag"
RSYNC_CMD=( rsync -avH --delete --exclude='.git/' --exclude='.hg/'
            --exclude='_build/' --exclude='*.beam' --exclude='*.o'
            --exclude='*.so' )

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

    ${RSYNC_CMD[@]} -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" \
        "$SOURCE_PROJECT_DIR"/. "vagrant@default:${VAGRANT_PROJECT_BUILD_DIR}"

    # Keep track of the project VCS tag
    if [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
        PROJECT_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$SOURCE_PROJECT_DIR" )"
        echo "$PROJECT_VCS_TAG" \
            | ssh -F "${GLB_TOP_DIR}/.vagrant.ssh_config" \
                "vagrant@default" \
                "cat > ${VAGRANT_PROJECT_BUILD_DIR}/${VCS_TAG_FILE}"
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
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_TARGET" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$VAGRANT_PROJECT_BUILD_DIR" )
    NEW_ARGS=( ${NEW_ARGS[@]} "$ARG_PROJECT_PROFILE" )

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap "cd '$GLB_TOP_DIR'; vagrant halt" EXIT
    fi
    cd "$GLB_TOP_DIR"
    vagrant exec "${GLB_VAGRANT_TOP_DIR}/build-project.sh" "${NEW_ARGS[@]}"
    exit $?
fi

# NATIVE LINUX EXECUTION STARTS HERE

# Clean SDK if requested (forces full rebuild)
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$GLB_SDK_BASE_DIR/*"
fi

# SDK INSTALLATION
install_sdk

# PROJECT MANAGMENT PLUGIN: Loads and sets up project management plugins
source "${GLB_SCRIPT_DIR}/plugins/project.sh"
project_setup

# PROJECT BUILD PREPARATION
PROJECT_DIR="${GLB_PROJECT_BUILD_DIR}/builds/${PROJECT_NAME}"
PACKAGE_DIR="${GLB_PROJECT_BUILD_DIR}/packages/${PROJECT_NAME}"
GLB_VCS_TAG="unknown"
if [[ -d "${GLB_TOP_DIR}/.git" ]]; then
    GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -c "$GLB_TOP_DIR" )"
elif [[ -f "${GLB_TOP_DIR}/${VCS_TAG_FILE}" ]]; then
    GLB_VCS_TAG="$( cat "${GLB_TOP_DIR}/${VCS_TAG_FILE}" )"
fi

# Clean previous builds if requested
if [[ $ARG_CLEAN == true ]]; then
    rm -rf "$PROJECT_DIR"
    rm -rf "$PACKAGE_DIR"
fi

# PROJECT TYPE DETECTION
project_detect PROJECT_TYPE "$SOURCE_PROJECT_DIR"

# Copy source project to build directory and prepare for compilation
echo "Building $PROJECT_TYPE project..."
mkdir -p "$PROJECT_DIR"
${RSYNC_CMD[@]} "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/${VCS_TAG_FILE}" ]] \
        && [[ -d "$SOURCE_PROJECT_DIR/.git" ]]; then
    "${GLB_SCRIPT_DIR}/git-info.sh" -c "$SOURCE_PROJECT_DIR" \
        -o "$PROJECT_DIR/${VCS_TAG_FILE}"
fi
mkdir -p "$PACKAGE_DIR"

# PROJECT COMPILATION
cd "$PROJECT_DIR"
PROJECT_VCS_TAG="unknown"
if [[ -f "$VCS_TAG_FILE" ]]; then
    PROJECT_VCS_TAG="$( cat "$VCS_TAG_FILE" )"
fi
# Set up cross-compilation environment (TARGET_ERLANG, etc.)
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"
rm -rf "_build/"

# build project using plugin
project_build RELEASE_DIR "$PROJECT_DIR" "$ARG_PROJECT_PROFILE" "$TARGET_ERLANG"
if [[ ! -d "$RELEASE_DIR" ]]; then
    error 1 "Failed to build $PROJECT_TYPE project in $RELEASE_DIR"
fi

APP_NAME="$( basename "$RELEASE_DIR" )"
APP_VER=""
APP_REL_DIR=$( echo "${RELEASE_DIR}/lib/${APP_NAME}-"* )
if [[ -d $APP_REL_DIR ]]; then
    APP_VER="$( echo "$APP_REL_DIR" | sed "s|^.*/${APP_NAME}-\(.*\)$|\1|" )"
fi

TARBALL_BASENAME="${APP_NAME}-${APP_VER}-${GLB_TARGET_NAME}"
if [[ "$ARG_PROJECT_PROFILE" != "default" ]]; then
    TARBALL_BASENAME="${TARBALL_BASENAME}-${ARG_PROJECT_PROFILE}"
fi
TARBALL_FILE="${GLB_ARTEFACTS_DIR}/${TARBALL_BASENAME}.tgz"

rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR/release"
cp -R "$RELEASE_DIR"/. "$PACKAGE_DIR/release/"

# Emit ALLOY-PROJECT manifest (bash-friendly)
MANIFEST_FILE="$PACKAGE_DIR/ALLOY-PROJECT"
cat << EOF > "$MANIFEST_FILE"
PROJECT_APP_NAME="${APP_NAME}"
PROJECT_APP_VERSION="${APP_VER}"
PROJECT_TYPE="${PROJECT_TYPE}"
PROJECT_PROFILE="${ARG_PROJECT_PROFILE}"
PROJECT_TARGET_NAME="${GLB_TARGET_NAME}"
PROJECT_COMMON_SYSTEM_VER="${GLB_COMMON_SYSTEM_VER}"
PROJECT_TARGET_SYSTEM_VER="${GLB_TARGET_SYSTEM_VER}"
PROJECT_ARCH="${CROSSCOMPILE_ARCH}"
PROJECT_VCS_PROJECT="${PROJECT_VCS_TAG}"
PROJECT_VCS_ALLOY="${GLB_VCS_TAG}"
EOF

# Emit ALLOY-FS-PRIORITIES (empty for now)
touch "$PACKAGE_DIR/ALLOY-FS-PRIORITIES"

# Create tarball
mkdir -p "$( dirname "$TARBALL_FILE" )"
tar -C "$PACKAGE_DIR" -czf "$TARBALL_FILE" .

echo "Project artefact created: $( basename "$TARBALL_FILE" )"

echo "Done"

exit 0
