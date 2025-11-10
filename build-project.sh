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
    error 1 "cannot find Erlang project $ARG_PROJECT"
fi

SOURCE_PROJECT_DIR="$( cd $ARG_PROJECT; pwd )"
PROJECT_NAME="$( basename "$SOURCE_PROJECT_DIR" )"
VCS_TAG_FILE=".alloy_vcs_tag"
RSYNC_CMD=( rsync -aqH --delete --exclude='_build/' --exclude='*.beam' \
            --exclude='*.o' --exclude='*.so' )

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
    if [[ ${ARG_DEBUG_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--debug" )
    fi
    if [[ ${ARG_CLEAN_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--clean" )
    fi
    if [[ ${ARG_PROJECT_PROFILE_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--profile" "$ARG_PROJECT_PROFILE" )
    fi
    NEW_ARGS+=( "$ARG_TARGET" )
    NEW_ARGS+=( "$VAGRANT_PROJECT_BUILD_DIR" )

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
    GLB_VCS_TAG="$( "${GLB_SCRIPT_DIR}/git-info.sh" -D -c "$GLB_TOP_DIR" )"
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
echo ${RSYNC_CMD[@]} "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
${RSYNC_CMD[@]} -v "$SOURCE_PROJECT_DIR"/. "$PROJECT_DIR"
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
# Set up cross-compilation environment (TARGET_ERLANG, etc.)
source "${GLB_SCRIPT_DIR}/grisp-env.sh" "$GLB_TARGET_NAME"
rm -rf "_build/"

# build project using plugin
project_build RELEASE_DIR "$PROJECT_DIR" "$ARG_PROJECT_PROFILE" "$TARGET_ERLANG"
if [[ ! -d "$RELEASE_DIR" ]]; then
    error 1 "Failed to build $PROJECT_TYPE project in $RELEASE_DIR"
fi
APP_NAME=""
APP_VER=""
RELEASE_NAME=""
RELEASE_VERSION=""
project_metadata APP_NAME APP_VER RELEASE_NAME RELEASE_VERSION "$RELEASE_DIR" "$PROJECT_DIR"

TARBALL_BASENAME="${RELEASE_NAME}-${RELEASE_VERSION}-${GLB_TARGET_NAME}"
if [[ -n "${ARG_PROJECT_PROFILE:-}" ]] && [[ "$ARG_PROJECT_PROFILE" != "default" ]]; then
    PROFILE_SEGMENT="$( echo "$ARG_PROJECT_PROFILE" | tr ',;:/ ' '-' | sed 's/--\+/-/g; s/^-//; s/-$//' )"
    if [[ -n "$PROFILE_SEGMENT" ]]; then
        TARBALL_BASENAME="${TARBALL_BASENAME}-${PROFILE_SEGMENT}"
    fi
fi
TARBALL_FILE="${GLB_ARTEFACTS_DIR}/${TARBALL_BASENAME}.tgz"

###############################################################################
# Release validations
###############################################################################

# Validate ERTS directory exists
ERTS_DIR_CANDIDATE=$( echo "${RELEASE_DIR}/erts-"* )
if [[ ! -d "$ERTS_DIR_CANDIDATE" ]] || [[ "$ERTS_DIR_CANDIDATE" == "${RELEASE_DIR}/erts-*" ]]; then
    echo "ERROR: Missing release erts directory"
    echo "To be compatible with GRiSP Alloy, the project must release the ERTS runtime"
    echo "e.g."
    echo "    rebar.config:"
    echo "        {relx, [{release, {...}, [...]}, {include_erts, true}, ...]}"
    echo "    mix.exs:"
    echo "        releases: [foobar: [..., include_erts: true, ...]]"
    echo
    exit 1
fi

# Validate lib/<APP>-<VERSION>
if [[ -z "$APP_VER" ]] || [[ ! -d "${RELEASE_DIR}/lib/${APP_NAME}-${APP_VER}" ]]; then
    error 1 "Missing release path lib/${APP_NAME}-${APP_VER}"
fi

# Validate releases/<RELEASE_NAME> (any string)
RELEASES_DIR_CANDIDATE="$( find "${RELEASE_DIR}/releases" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 )"
if [[ -z "$RELEASES_DIR_CANDIDATE" ]] || [[ ! -d "$RELEASES_DIR_CANDIDATE" ]]; then
    error 1 "Missing release path under releases/"
fi

# Extract ERTS version (strip leading 'erts-')
RELEASE_ERTS_VERSION="$( basename "$ERTS_DIR_CANDIDATE" | sed 's/^erts-//' )"
if [[ -z "$RELEASE_ERTS_VERSION" ]]; then
    error 1 "Missing release erts directory"
fi

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
PROJECT_CROSSCOMPILE_ARCH="${CROSSCOMPILE_ARCH}"
PROJECT_ERTS_VERSION="${RELEASE_ERTS_VERSION}"
PROJECT_RELEASE_NAME="${RELEASE_NAME}"
PROJECT_RELEASE_VERSION="${RELEASE_VERSION}"
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
