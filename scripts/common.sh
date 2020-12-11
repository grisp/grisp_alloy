# Common setup for all the scripts.
# For a script in the same directory, it should be sourced with:
#     source "$( dirname "$0" )/common.sh"

error() {
    local code="$1"
    shift
    local msg="$*"
    echo "ERROR: $msg ($code)"
    exit $code
}

# "readlink -f" implementation for BSD
# This code was extracted from the Elixir shell scripts
readlink_f () {
    cd "$(dirname "$1")" > /dev/null
    filename="$(basename "$1")"
    if [[ -h "$filename" ]]; then
        readlink_f "$(readlink "$filename")"
    else
        echo "$(pwd -P)/$filename"
    fi
}

# OS and architecture detection
BUILD_ARCH="$(uname -m)"
BUILD_OS="$(uname -s)"
case "$BUILD_OS" in
    "CYGWIN_NT-6.1") BUILD_OS="cygwin";;
esac
BUILD_OS="$(echo "$BUILD_OS" | awk '{print tolower($0)}')"
HOST_ARCH="${HOST_ARCH:-$BUILD_ARCH}"
HOST_OS="${HOST_OS:-$BUILD_OS}"

# Command compatibility
case "$BUILD_OS" in
    linux)
        READLINK=readlink
        TAR=tar
        AWK=awk
        ;;
    darwin)
        READLINK=greadlink
        TAR=gtar
        AWK=awk
        ;;
    cygwin | freebsd)
        READLINK=readlink
        TAR=tar
        AWK=gawk
        ;;
    *)
        error 1 "Unsupported host OS: $BUILD_OS"
        ;;
esac

# Absolute Paths
GLB_SCRIPT_DIR="$(readlink_f "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )"
GLB_TOP_DIR="$( cd "$GLB_SCRIPT_DIR" && cd .. && pwd )"
GLB_ARTEFACTS_DIR="${GLB_TOP_DIR}/artefacts"
GLB_CACHE_DIR="${GLB_TOP_DIR}/_cache"
GLB_BUILD_DIR="${GLB_TOP_DIR}/_build"
GLB_TOOLCHAIN_DIR="${GLB_TOP_DIR}/toolchain"
GLB_TOOLCHAIN_CACHE_DIR="${GLB_CACHE_DIR}/toolchain"
GLB_TOOLCHAIN_SCRIPT_DIR="${GLB_TOOLCHAIN_DIR}/scripts"
GLB_TOOLCHAIN_PATCH_DIR="${GLB_TOOLCHAIN_DIR}/patches"
GLB_TOOLCHAIN_BUILD_DIR="${GLB_TOP_DIR}/_build/toolchain"
GLB_SYSTEM_DIR="${GLB_TOP_DIR}/system_common"
GLB_SYSTEM_CACHE_DIR="${GLB_CACHE_DIR}/system"
GLB_SYSTEM_SCRIPT_DIR="${GLB_SYSTEM_DIR}/scripts"
GLB_SYSTEM_BUILD_DIR="${GLB_TOP_DIR}/_build/system"
GLB_SDK_NAME="grisp_linux_sdk"
GLB_SDK_BASE_DIR="/opt/${GLB_SDK_NAME}"

GLB_DEBUG="${GLB_DEBUG:-0}"

set_debug_level()
{
    local debug="$1"
    if [[ $debug -eq 0 ]]; then
        set +x
    elif [[ $debug -gt 0 ]]; then
        set -x
    fi
    export GLB_DEBUG="$debug"
}

enter_hidden() {
    if [[ $GLB_DEBUG -gt 0 ]]; then
        set +x
    fi
}

leave_hidden() {
    if [[ $GLB_DEBUG -gt 0 ]]; then
        set -x
    fi
}

read_defconfig_key() {
    enter_hidden
    local config="$1"
    local key="$2"
    echo "$( source $config && echo "${!key}" )"
    leave_hidden
}

trim() {
    local msg="$*"
    echo "$( echo "$msg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' )"
}

checkpoint()
{
    local name="$1"
    local dir="$2"
    shift
    shift
    local args=("${@}")
    if [[ ! -f "${dir}/${name}" ]]; then
        $name "${arg[@]}"
    fi
    touch "${dir}/${name}"
}

set_debug_level "$GLB_DEBUG"