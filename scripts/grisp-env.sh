# Script that should be sourced to setup your environment to cross-compile
# and build Erlang apps for this Grisp build.

if [[ $SHELL == "/bin/bash" ]] || [[ $SHELL == "/bin/zsh" ]]; then
    SCRIPT_SOURCE="${BASH_SOURCE[0]:-${(%):-%x}}"
    if [[ $0 == $SCRIPT_SOURCE ]]; then
        echo "ERROR: the script grisp-env.sh must be sourced"
        exit 1
    fi
    SCRIPT_DIR="$( dirname $SCRIPT_SOURCE )"
fi

# From there we know we are sourced, so we shouldn't call exit (or error)

source "${SCRIPT_DIR}/common.sh"

if [[ ! -d $GLB_SDK_DIR ]] || [[ ! -d $GLB_SDK_HOST_DIR ]]; then
	if [[ $GLB_IS_SDK == false ]]; then
		if [[ -z $GLB_TARGET_NAME ]]; then
			echo "ERROR: Target not specified"
			echo "USAGE: source grisp-env.sh TARGET"
			return 1
		fi
	fi
	echo "ERROR: Grisp SDK not found in $GLB_SDK_DIR"
	return 1
fi

GRISP_SDK_ROOT="${GLB_SDK_DIR}"
GRISP_SDK_HOST="${GLB_SDK_HOST_DIR}"
GRISP_SDK_IMAGES="${GLB_SDK_DIR}/images"
GRISP_SDK_SYSROOT="${GLB_SDK_DIR}/staging"

CROSSCOMPILE_PREFIX=$( find "${GRISP_SDK_HOST}/bin/" -maxdepth 1 -name "*gcc" | sed -e s/-gcc// | head -n 1 )
if [[ -z $CROSSCOMPILE_PREFIX ]]; then
	echo "ERROR: SDK cross-compiler not found in ${GRISP_SDK_HOST}/bin"
	return 1
fi
CROSSCOMPILE_ARCH=$( basename "$CROSSCOMPILE_PREFIX" )

export GRISP_SDK_ROOT
export GRISP_SDK_HOST
export GRISP_SDK_IMAGES
export GRISP_SDK_SYSROOT

add_to_var PATH "${GRISP_SDK_HOST}/bin"
add_to_var LD_LIBRARY_PATH "${GRISP_SDK_HOST}/lib"

# Erlang, rebar and C/C++ exports
ERTS_DIR=$( ls -d "${GRISP_SDK_SYSROOT}/usr/lib/erlang/erts-"* )
ERL_INTERFACE_DIR=$( ls -d "${GRISP_SDK_SYSROOT}/usr/lib/erlang/lib/erl_interface-"* )
export CROSSCOMPILE_ARCH
export REBAR_TARGET_ARCH="$CROSSCOMPILE_ARCH"
export CROSSCOMPILE="$CROSSCOMPILE_PREFIX"
export HOST_ERLANG="${GRISP_SDK_HOST}/usr/lib/erlang"
export TARGET_ERLANG="${GRISP_SDK_SYSROOT}/usr/lib/erlang"
export ERL_LIBS="${TARGET_ERLANG}/lib"
export REBAR_PLT_DIR="${TARGET_ERLANG}"
export CC="${CROSSCOMPILE}-gcc"
export CXX="${CROSSCOMPILE}-g++"
export CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64  -pipe -O2 -I$GRISP_SDK_SYSROOT/usr/include"
export CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64  -pipe -O2 -I$GRISP_SDK_SYSROOT/usr/include"
export LDFLAGS="--sysroot=$GRISP_SDK_SYSROOT"
export STRIP="${CROSSCOMPILE}-strip"
export ERL_CFLAGS="-I${ERTS_DIR}/include -I${ERL_INTERFACE_DIR}/include"
export ERL_LDFLAGS="-L${ERTS_DIR}/lib -L${ERL_INTERFACE_DIR}/lib -lerts -lei"

# pkg-config
export PKG_CONFIG="${GRISP_SDK_HOST}/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="$GRISP_SDK_SYSROOT"
export PKG_CONFIG_LIBDIR="$GRISP_SDK_SYSROOT/usr/lib/pkgconfig"

# Rebar naming
export ERL_EI_LIBDIR="${ERL_INTERFACE_DIR}/lib"
export ERL_EI_INCLUDE_DIR="${ERL_INTERFACE_DIR}/include"

# erlang.mk naming
export ERTS_INCLUDE_DIR="${ERTS_DIR}/include"
export ERL_INTERFACE_LIB_DIR="${ERL_INTERFACE_DIR}/lib"
export ERL_INTERFACE_INCLUDE_DIR="${ERL_INTERFACE_DIR}/include"

# Host tools
export AR_FOR_BUILD=ar
export AS_FOR_BUILD=as
export CC_FOR_BUILD=cc
export GCC_FOR_BUILD=gcc
export CXX_FOR_BUILD=g++
export LD_FOR_BUILD=ld
export CPPFLAGS_FOR_BUILD=
export CFLAGS_FOR_BUILD=
export CXXFLAGS_FOR_BUILD=
export LDFLAGS_FOR_BUILD=

echo "*************************************************"
echo "*** CROSS-COMPILATION ENVIRONMENT INITIALIZED ***"
echo "*************************************************"
echo " Grisp Target:   $GLB_TARGET_NAME"
echo " Target Arch:    $CROSSCOMPILE_ARCH"
echo " Common Version: $GLB_COMMON_SYSTEM_VER"
echo " Target Version: $GLB_TARGET_SYSTEM_VER"
echo "*************************************************"
echo

PROMPT_POSTFIX="[$GLB_TARGET_NAME sdk]"
if [[ $PS1 != *"${PROMPT_POSTFIX} " ]]; then
	PS1="${PS1}${PROMPT_POSTFIX} "
fi

return 0
