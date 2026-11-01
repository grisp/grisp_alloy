# shellcheck shell=bash
# Source this to select the SDK's target C toolchain, sysroot, flags, and host
# tools in an interactive shell or build script. It does not set language
# environments; project-env.sh adds those for each project build.
_cross_environment_setup() {
    local prefix=""
    local sdk_gcc sdk_root path_variable path_value path_current
    if [[ -z ${GLB_SDK_DIR:-} ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/common.sh" "${1:-}" || return $?
    fi
    if [[ ! -d $GLB_SDK_DIR || ! -d $GLB_SDK_HOST_DIR ]]; then
        echo "ERROR: Grisp SDK not found in ${GLB_SDK_DIR:-}; source grisp-env.sh TARGET" >&2
        return 1
    fi
    if [[ -n ${1:-} && ${GLB_TARGET_NAME:-} != "$1" ]]; then
        echo "ERROR: Environment target '$1' differs from selected SDK target '${GLB_TARGET_NAME:-}'" >&2
        return 1
    fi
    sdk_root="$(cd "$GLB_SDK_DIR" && pwd -P)" || return 1
    if [[ -n ${_GRISP_CROSS_SDK_DIR:-} && $_GRISP_CROSS_SDK_DIR != "$sdk_root" ]]; then
        echo "ERROR: Another SDK environment is already active; use a fresh shell" >&2
        return 1
    fi
    for sdk_gcc in "$GLB_SDK_HOST_DIR"/bin/*-gcc; do
        [[ -x $sdk_gcc ]] || continue
        if [[ -n $prefix ]]; then
            echo "ERROR: Multiple SDK cross-compilers in $GLB_SDK_HOST_DIR/bin" >&2
            return 1
        fi
        prefix="${sdk_gcc%-gcc}"
    done
    if [[ -z $prefix ]]; then
        echo "ERROR: SDK cross-compiler not found in $GLB_SDK_HOST_DIR/bin" >&2
        return 1
    fi

    export GRISP_SDK_ROOT="$GLB_SDK_DIR" GRISP_SDK_HOST="$GLB_SDK_HOST_DIR"
    export GRISP_SDK_IMAGES="$GLB_SDK_DIR/images" GRISP_SDK_SYSROOT="$GLB_SDK_DIR/staging"
    CROSSCOMPILE_PREFIX="$prefix"
    export CROSSCOMPILE="$prefix" CROSSCOMPILE_ARCH="${prefix##*/}"
    for path_variable in PATH LD_LIBRARY_PATH; do
        case "$path_variable" in
            PATH) path_value="$GRISP_SDK_HOST/bin" ;;
            LD_LIBRARY_PATH) path_value="$GRISP_SDK_HOST/lib" ;;
        esac
        path_current="${!path_variable:-}"
        if [[ -d $path_value && ":$path_current:" != *":$path_value:"* ]]; then
            printf -v "$path_variable" '%s' "$path_value${path_current:+:$path_current}"
        fi
        export "${path_variable?}"
    done
    export CC="${CROSSCOMPILE}-gcc" CXX="${CROSSCOMPILE}-g++"
    export CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64  -pipe -O2 -I$GRISP_SDK_SYSROOT/usr/include"
    export CXXFLAGS="$CFLAGS" LDFLAGS="--sysroot=$GRISP_SDK_SYSROOT" STRIP="${CROSSCOMPILE}-strip"
    export PKG_CONFIG="$GRISP_SDK_HOST/bin/pkg-config" PKG_CONFIG_SYSROOT_DIR="$GRISP_SDK_SYSROOT"
    export PKG_CONFIG_LIBDIR="$GRISP_SDK_SYSROOT/usr/lib/pkgconfig"
    export AR_FOR_BUILD=ar AS_FOR_BUILD=as CC_FOR_BUILD=cc GCC_FOR_BUILD=gcc CXX_FOR_BUILD=g++ LD_FOR_BUILD=ld
    export CPPFLAGS_FOR_BUILD='' CFLAGS_FOR_BUILD='' CXXFLAGS_FOR_BUILD='' LDFLAGS_FOR_BUILD=''
    export _GRISP_CROSS_SDK_DIR="$sdk_root"
}

_cross_environment_setup "${1:-}"
