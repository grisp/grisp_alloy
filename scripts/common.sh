# Common setup for all the scripts.
# For a script in the same directory, it should be sourced with:
#     source "$( dirname "$0" )/common.sh"
#
# If called from the grisp_limnux_builder repo, a target name is expected
# as the first parameter.

ARG_TARGET="$1"

error() {
    local code="$1"
    shift
    local msg="$*"
    echo "ERROR: $msg ($code)" 1>&2
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

add_to_var() {
    local var="$1"
    local val="$2"
    if [[ -d $val ]]; then
        if [[ -z ${!var} ]]; then
            eval "${var}=\"${val}\""
        elif [[ ":${!var}:" != *":${val}:"* ]]; then
            eval "$var=\"${val}:\$${var}\""
        fi
    fi
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

# Ensure SDK is installed (rootfs, toolchain, base packages)
install_sdk() {
    if [[ ! -d $GLB_SDK_DIR ]]; then
        echo "SDK not installed, trying to install it from artefacts..."
        if [[ ! -f "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}" ]]; then
            error 1 "SDK ${GLB_SDK_FILENAME} not found in ${GLB_ARTEFACTS_DIR}"
        fi
        if [[ ! -d $GLB_SDK_BASE_DIR ]]; then
            mkdir -p "$GLB_SDK_BASE_DIR"
            chgrp "$USER" "$GLB_SDK_BASE_DIR"
            chmod 775 "$GLB_SDK_BASE_DIR"
        fi
        tar -C "$GLB_SDK_BASE_DIR" --strip-components=1 -xzf \
            "${GLB_ARTEFACTS_DIR}/${GLB_SDK_FILENAME}"
        if [[ ! -d $GLB_SDK_DIR ]]; then
            error 1 "SDK ${GLB_SDK_FILENAME} is invalid"
        fi
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

GLB_SCRIPT_DIR="$(readlink_f "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )"
GLB_TOP_DIR="$( cd "$GLB_SCRIPT_DIR" && cd .. && pwd )"
GLB_VAGRANT_TOP_DIR="/home/vagrant"
GLB_SDK_NAME="grisp_alloy_sdk"
GLB_SDK_PARENT_DIR="/opt"
GLB_SDK_BASE_DIR="${GLB_SDK_PARENT_DIR}/${GLB_SDK_NAME}"

if [[ $GLB_TOP_DIR == ${GLB_SDK_BASE_DIR}* ]]; then
    # running the sdk version
    GLB_IS_SDK=true
    SDK_DIR_REGEX="${GLB_SDK_BASE_DIR}/\([0-9.]*\)/\([0-9a-z_]*\)/\([0-9.]*\)"
    GLB_COMMON_SYSTEM_VER=$( echo "$GLB_TOP_DIR" | sed "s|${SDK_DIR_REGEX}|\1|" )
    [[ ! -z $GLB_COMMON_SYSTEM_VER ]]
    GLB_TARGET_NAME=$( echo "$GLB_TOP_DIR" | sed "s|${SDK_DIR_REGEX}|\2|" )
    [[ ! -z $GLB_TARGET_NAME ]]
    GLB_TARGET_SYSTEM_VER=$( echo "$GLB_TOP_DIR" | sed "s|${SDK_DIR_REGEX}|\3|" )
    [[ ! -z $GLB_TARGET_SYSTEM_VER ]]
    GLB_SDK_DIR="${GLB_TOP_DIR}"
    GLB_SDK_HOST_DIR="${GLB_SDK_DIR}/host"
else
    # running the builder version
    GLB_IS_SDK=false
    GLB_ARTEFACTS_DIR="${GLB_TOP_DIR}/artefacts"
    GLB_VAGRANT_ARTEFACTS_DIR="${GLB_VAGRANT_TOP_DIR}/artefacts"
    GLB_CACHE_DIR="${GLB_TOP_DIR}/_cache"
    GLB_BUILD_DIR="${GLB_TOP_DIR}/_build"
    GLB_VAGRANT_BUILD_DIR="${GLB_VAGRANT_TOP_DIR}/_build"
    GLB_TOOLCHAIN_DIR="${GLB_TOP_DIR}/toolchain"
    GLB_TOOLCHAIN_CACHE_DIR="${GLB_CACHE_DIR}/toolchain"
    GLB_TOOLCHAIN_SCRIPT_DIR="${GLB_TOOLCHAIN_DIR}/scripts"
    GLB_TOOLCHAIN_PATCH_DIR="${GLB_TOOLCHAIN_DIR}/patches"
    GLB_TOOLCHAIN_BUILD_DIR="${GLB_BUILD_DIR}/toolchain"
    GLB_SYSTEM_DIR="${GLB_TOP_DIR}/system_common"
    GLB_SYSTEM_CACHE_DIR="${GLB_CACHE_DIR}/system"
    GLB_SYSTEM_SCRIPT_DIR="${GLB_SYSTEM_DIR}/scripts"
    GLB_SYSTEM_BUILD_DIR="${GLB_BUILD_DIR}/system"
    GLB_PROJECT_BUILD_DIR="${GLB_BUILD_DIR}/project"
    GLB_VAGRANT_PROJECT_BUILD_DIR="${GLB_VAGRANT_BUILD_DIR}/project"
    GLB_FIRMWARE_BUILD_DIR="${GLB_BUILD_DIR}/firmware"
    GLB_VAGRANT_FIRMWARE_BUILD_DIR="${GLB_VAGRANT_BUILD_DIR}/firmware"

    if [[ ! -z $ARG_TARGET ]] && [[ -d "$GLB_TOP_DIR/system_${ARG_TARGET}" ]]; then
        GLB_TARGET_NAME="$ARG_TARGET"
        GLB_COMMON_SYSTEM_DIR="$GLB_TOP_DIR/system_common"
        GLB_TARGET_SYSTEM_DIR="$GLB_TOP_DIR/system_${GLB_TARGET_NAME}"
        GLB_COMMON_SYSTEM_VER="$( cat "${GLB_COMMON_SYSTEM_DIR}/VERSION" )"
        GLB_TARGET_SYSTEM_VER="$( cat "${GLB_TARGET_SYSTEM_DIR}/VERSION" )"
        GLB_SDK_DIR="${GLB_SDK_BASE_DIR}/${GLB_COMMON_SYSTEM_VER}/${GLB_TARGET_NAME}/${GLB_TARGET_SYSTEM_VER}"
        GLB_SDK_HOST_DIR="${GLB_SDK_DIR}/host"
        GLB_SDK_FILENAME="${GLB_SDK_NAME}-${GLB_COMMON_SYSTEM_VER}-${GLB_TARGET_NAME}-${GLB_TARGET_SYSTEM_VER}-${HOST_OS}-${HOST_ARCH}.tar.gz"
    fi
fi

GLB_DEBUG="${GLB_DEBUG:-0}"
set_debug_level "$GLB_DEBUG"
