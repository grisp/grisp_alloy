#!/usr/bin/env bash

# Even though the compatibility code for darwin, freebsd and cygwin has been
# kept, it has not yet been tested and probably doesn't work.

# Inspired by Nerves' Crosstool-NG build script:
#   https://github.com/nerves-project/toolchains/blob/main/nerves_toolchain_ctng/build.sh

# Usage: build-crosstool-ng.sh TARGET_NAME DEFCONFIG
# e.g.   build-crosstool-ng.sh grisp2 ../configs/grisp2_linux_x86_64_defconfig

set -e

TARGET="$1"
SOURCE_DEFCONFIG="$2"

usage()
{
    echo "USAGE: build-crosstool-ng.sh TARGET_NAME DEFCONFIG_FILE"
    exit 1
}

[[ -z $TARGET ]] && usage
[[ -z $SOURCE_DEFCONFIG ]] && usage

if [[ ! -e $SOURCE_DEFCONFIG ]]; then
    error 1 "Cannot find toolchain configuration $SOURCE_DEFCONFIG"
fi

source "${GLB_TOP_DIR:-$( dirname "$0" )/../..}/scripts/common.sh" "$TARGET"

# Read our custom configuration from the defconfig file
TOOLCHAIN_VERSION="$( read_defconfig_key "$SOURCE_DEFCONFIG" GLB_TOOLCHAIN_VERSION )"
TOOLCHAIN_VERSION="$( trim "$TOOLCHAIN_VERSION" )"
if [[ -z $TOOLCHAIN_VERSION ]]; then
    error 1 "Cannot find toolchain version GLB_TOOLCHAIN_VERSION in toolchain configuration file $SOURCE_DEFCONFIG"
fi
CTNG_USE_GIT="$( trim $( read_defconfig_key "$SOURCE_DEFCONFIG" GLB_CTNG_USE_GIT ) )"
[[ -z $CTNG_USE_GIT ]] && CTNG_USE_GIT=false
CTNG_TAG="$( trim $( read_defconfig_key "$SOURCE_DEFCONFIG" GLB_CTNG_TAG ) )"
if [[ -z $CTNG_TAG ]]; then
    error 1 "Cannot find Crosstool-NG tag GLB_CTNG_TAG in toolchain configuration file $SOURCE_DEFCONFIG"
fi

ROOT_DIR="${GLB_TOOLCHAIN_BUILD_DIR}/crosstool-ng"
WORK_DIR="${ROOT_DIR}"
INSTALL_DIR="${ROOT_DIR}/x-tools"
BUILD_DIR="${ROOT_DIR}/build"
CT_BUILD_DIR="${ROOT_DIR}/build"
LOCAL_INSTALL_DIR="${ROOT_DIR}/usr"
CTNG_ARCHIVE_NAME="crosstool-ng-$CTNG_TAG.tar.xz"
CTNG_ARCHIVE_FILE="${GLB_ARTEFACTS_DIR}/${CTNG_ARCHIVE_NAME}"
WORK_DIR_IS_GLOBAL="false"
CHECKPOINTS_DIR="${ROOT_DIR}/checkpoints"
CLEAN="${CLEAN:-false}"

#### Environment preparation and validation ####

case "$BUILD_OS" in
    darwin)
        WORK_DMG="$WORK_DIR.dmg"
        WORK_DMG_VOLNAME="$( basename "$WORK_DIR" )"

        export CURSES_LIBS="-L/usr/local/opt/ncurses/lib -lncursesw"
        CROSSTOOL_LDFLAGS="-L/usr/local/opt/gettext/lib -lintl"
        CROSSTOOL_CFLAGS="-I/usr/local/opt/gettext/include"

        export PATH="/usr/local/opt/bison/bin:$PATH"
        if [[ ! -e /usr/local/opt/bison/bin/bison ]]; then
            error 1 "Building gcc requires a more recent version on bison than Apple provides. Install with 'brew install bison'"
        fi

        export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
        if [[ ! -e /usr/local/opt/grep/libexec/gnubin/grep ]]; then
            error 1 "Building gcc requires GNU grep. Install with 'brew install grep'"
        fi
        ;;
    linux)
        # Long path lengths cause gcc builds to fail. This is due to argument
        # length exceeded errors from long Make commandlines. To work around this
        # issue, we tell crosstool-ng to do its work under /tmp/ctng-work. This
        # forces one build at a time.
        WORK_DIR="/tmp/ctng-work"
        CT_BUILD_DIR="/tmp/ctng-work/build"
        WORK_DIR_IS_GLOBAL="true"
        ;;
esac

SOURCE_DIR_NAME="crosstool-ng"
SOURCE_DIR="${WORK_DIR}/${SOURCE_DIR_NAME}"
TOOLCHAIN_DEFCONFIG="${BUILD_DIR}/defconfig"
TOOLCHAIN_DEFCONFIG_ORIG="${BUILD_DIR}/defconfig.orig"
CTNG="$LOCAL_INSTALL_DIR/bin/ct-ng"

# Be sure we have a large enough number of files
ulimit_n=$(ulimit -n)
if [[ ${ulimit_n} < 2048 ]]; then
    echo "Increasing number of open file to 2048"
    ulimit -n 2048
fi

# crosstool-ng needs the AWK variable when using awk variant
export AWK

if [[ $CLEAN == "true" ]]; then
    rm -rf "$CHECKPOINTS_DIR"
fi

prepare_environment()
{
    echo "Preparing environment..."

    case "$BUILD_OS" in
        darwin)
            hdiutil detach "/Volumes/$WORK_DMG_VOLNAME" 2>/dev/null || true
            rm -rf "$WORK_DIR" "$WORK_DMG"
            hdiutil create -size 10g -fs "Case-sensitive HFS+" -volname "$WORK_DMG_VOLNAME" "$WORK_DMG"
            hdiutil attach "$WORK_DMG"
            ln -s "/Volumes/$WORK_DMG_VOLNAME" "$WORK_DIR"
            ;;
        linux | cygwin | freebsd)
            if [[ -e $WORK_DIR ]]; then
                chmod -R u+w "$WORK_DIR"
                rm -rf "$WORK_DIR"
            fi
            mkdir -p "$WORK_DIR"
    esac

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$GLB_ARTEFACTS_DIR"
    mkdir -p "$GLB_TOOLCHAIN_CACHE_DIR"
    mkdir -p "$CHECKPOINTS_DIR"
}

checkout_source_code()
{
    echo "Retrieving Crosstool-NG source code..."

    cd "$WORK_DIR"

    rm -rf "$SOURCE_DIR_NAME"

    if [[ ! -e $CTNG_ARCHIVE_FILE ]]; then
        if [ $CTNG_USE_GIT == "true" ]; then
            git clone https://github.com/crosstool-ng/crosstool-ng.git
            cd "$SOURCE_DIR_NAME"
            git config advice.detachedHead false
            git checkout "$CTNG_TAG"
            cd ..
            $TAR -c -J --exclude=.git -f "$CTNG_ARCHIVE_FILE" "$SOURCE_DIR_NAME"
        else
            curl -L -o "$CTNG_ARCHIVE_FILE" "http://crosstool-ng.org/download/crosstool-ng/$CTNG_ARCHIVE_NAME"
            $TAR xf "$CTNG_ARCHIVE_FILE"
            cd "$SOURCE_DIR_NAME"
        fi
    else
        $TAR xf "$CTNG_ARCHIVE_FILE"
        cd "$SOURCE_DIR_NAME"
    fi
    [ "$SOURCE_DIR" == "$( pwd )" ] || error 1 "Assert failed $0:$LINENO"
    "$GLB_SCRIPT_DIR/apply-patches.sh" "$SOURCE_DIR" "$GLB_TOOLCHAIN_PATCH_DIR/crosstool-ng"
}

build_crosstool_ng()
{
    echo "Building Crosstool-NG..."

    cd "$SOURCE_DIR"

    rm -rf "$LOCAL_INSTALL_DIR"

    if [[ $CTNG_USE_GIT == "true" ]]; then
        ./bootstrap
    fi
    case "$BUILD_OS" in
        darwin)
            CC=gcc-9 \
            CXX=g++-9 \
            OBJDUMP=/usr/local/Cellar/binutils/2.34/bin/gobjdump \
            OBJCOPY=/usr/local/Cellar/binutils/2.34/bin/gobjcopy \
            READELF=/usr/local/Cellar/binutils/2.34/bin/greadelf \
            CFLAGS="$CROSSTOOL_CFLAGS" \
            LDFLAGS="$CROSSTOOL_LDFLAGS" \
            SED=/usr/local/bin/gsed \
            MAKE=/usr/local/bin/gmake \
            ./configure --prefix="$LOCAL_INSTALL_DIR"
            gmake
            gmake install
            ;;
        freebsd)
            SED=/usr/local/bin/gsed \
            MAKE=/usr/local/bin/gmake \
            PATCH=/usr/local/bin/gpatch \
            ./configure --prefix="$LOCAL_INSTALL_DIR"
            gmake
            gmake install
            ;;
        *)
            ./configure --prefix="$LOCAL_INSTALL_DIR"
            make
            make install
            ;;
    esac

    # Check the build
    if [[ ! -e $LOCAL_INSTALL_DIR/bin/ct-ng ]]; then
        error 1 "Crosstool-NG build failed."
    fi
}

prepare_toolchain_build()
{
    echo "Preparing the toolchain build..."

    # Setup the toolchain build directory
    rm -rf "$BUILD_DIR"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    REL_CACHE_DIR="$( ${GLB_SCRIPT_DIR}/compute-relative.sh "$BUILD_DIR" "$GLB_TOOLCHAIN_CACHE_DIR" )"
    REL_INSTALL_DIR="$( ${GLB_SCRIPT_DIR}/compute-relative.sh "$BUILD_DIR" "$INSTALL_DIR" )"

    # Generate the configuration
    cat "$SOURCE_DEFCONFIG" | grep -v "^GLB_" > "$TOOLCHAIN_DEFCONFIG"
    cat >> "$TOOLCHAIN_DEFCONFIG" <<EOF

# Generated by the toolchain build script
CT_LOCAL_TARBALLS_DIR="$REL_CACHE_DIR"
CT_PREFIX_DIR="${REL_INSTALL_DIR}/\${CT_TARGET}"
EOF

    if [ $WORK_DIR_IS_GLOBAL == "true" ]; then
        echo "CT_WORK_DIR=\"${CT_BUILD_DIR}\"" >> "$TOOLCHAIN_DEFCONFIG"
    fi

    # Process the configuration
    $CTNG defconfig
    cp "$TOOLCHAIN_DEFCONFIG" "$TOOLCHAIN_DEFCONFIG_ORIG"
    $CTNG savedefconfig

    echo "defconfig:"
    cat "$TOOLCHAIN_DEFCONFIG"
}

toolchain_tuple()
{
    echo $( cd "$BUILD_DIR"; $CTNG show-tuple )
}

toolchain_tuple_underscores()
{
    toolchain_tuple | tr - _
}

build_toolchain()
{
    local target_tuple="$( toolchain_tuple )"
    echo "Building toolchain ${target_tuple}..."

    cd "$BUILD_DIR"

    rm -rf "$INSTALL_DIR"
    mkdir -p "$CT_BUILD_DIR" # In case it is different

    if [[ -z $CTNG_CC ]]; then
        PREFIX=""
    else
        PREFIX="CC=$CTNG_CC CXX=$CTNG_CXX"
    fi

    # Start building and print dots to keep CI from killing the build due
    # to console inactivity.
    unset LD_LIBRARY_PATH
    $PREFIX "$CTNG" build &
    local build_pid=$!
    enter_hidden
    {
        while ps -p $build_pid >/dev/null; do
           sleep 12
           printf "."
        done
    } &
    local keepalive_pid=$!
    leave_hidden

    # Wait for the build to finish
    wait $build_pid 2>/dev/null

    # Stop the keepalive task
    kill $keepalive_pid
    wait $keepalive_pid 2>/dev/null || true

    echo "Fixing permissions on release"
    # ct-ng likes to mark everything read-only which seems reasonable, but it
    # can be really annoying when trying to cleanup a toolchain.
    chmod -R u+w "$INSTALL_DIR/$target_tuple"
}

save_build_info()
{
    local target_tuple="$( toolchain_tuple )"
    echo "Gathering toolchain ${target_tuple} information..."

    echo "$TOOLCHAIN_VERSION" > "${INSTALL_DIR}/${target_tuple}/grisp-toolchain.tag"
    cp "$TOOLCHAIN_DEFCONFIG_ORIG" "${INSTALL_DIR}/${target_tuple}/ct-ng.defconfig"
    cp "$BUILD_DIR/.config" "${INSTALL_DIR}/${target_tuple}/ct-ng.config"
}

cleanup_toolchain()
{
    local target_tuple="$( toolchain_tuple )"
    echo "Cleaning up toolchain ${target_tuple}..."

    # Clean up the build product
    rm -f "${INSTALL_DIR}/${target_tuple}/build.log.bz2"

    # Clean up crosstool-ng's work directory if we put it in a global location
    if [[ $WORK_DIR_IS_GLOBAL == "true" ]]; then
        chmod -R u+w "$WORK_DIR"
        rm -fr "$WORK_DIR"
    fi
}

toolchain_base_name()
{
    # Compute the base filename part of the build product
    echo "grisp_toolchain_$( toolchain_tuple_underscores )-$TOOLCHAIN_VERSION.$HOST_OS-$HOST_ARCH"
}

create_archive()
{
    local target_tuple="$( toolchain_tuple )"
    local archive_file_name="$( toolchain_base_name ).tar.xz"
    echo "Building toolchain archive ${archive_file_name} ..."

    cd "${INSTALL_DIR}"
    tar -cf - "${target_tuple}" -P \
        | pv -s $(du -sb "${INSTALL_DIR}/${target_tuple}" \
        | awk '{print $1}') \
        | xz > "${GLB_ARTEFACTS_DIR}/${archive_file_name}"
}

assemble_dmg()
{
    # On Macs, the file system is case-preserving, but case-insensitive. The netfilter
    # module in the Linux kernel provides header files that differ only in case, so this
    # won't work if you need to use both the capitalized and lowercase versions of the
    # header files. Therefore, the workaround is to create a case-sensitive .dmg file.
    #
    # This can be annoying since you need to use hdiutil to mount it, etc., so we also
    # create a tarball for OSX users that don't use netfilter. Since the
    # Linux kernels don't even enable netfilter, it's likely that most
    # users will never notice.

    # Assemble the tarball for the toolchain
    local target_tuple="$( toolchain_tuple )"
    local dmg_file_name="$( toolchain_base_name ).dmg"
    local dmg_path="${WORK_DIR}/${dmg_file_name}"
    echo "Building toolchain DMG ${dmg_file_name} ..."

    rm -f "$DMG_PATH"
    hdiutil create -fs "Case-sensitive HFS+" -volname grisp-toolchain \
                    -srcfolder "${INSTALL_DIR}/${target_tuple}/." \
                    "$dmg_path"

    cp "$DMG_PATH" "${GLB_ARTEFACTS_DIR}/${dmg_file_name}"
}

fix_kernel_case_conflicts()
{
    # Remove case conflicts in the kernel include directory so that users don't need to
    # use case sensitive filesystems on OSX. See comment in assemble_dmg().
    local target_tuple=$( toolchain_tuple )
    echo "Fixing toolchain ${target_tuple} kernel includes casing ..."

    LINUX_INCLUDE_DIR=${INSTALL_DIR}/${target_tuple}/${target_tuple}/sysroot/usr/include/linux
    rm -f "${LINUX_INCLUDE_DIR}/netfilter/xt_CONNMARK.h" \
          "${LINUX_INCLUDE_DIR}/netfilter/xt_DSCP.h" \
          "${LINUX_INCLUDE_DIR}/netfilter/xt_MARK.h" \
          "${LINUX_INCLUDE_DIR}/netfilter/xt_RATEEST.h" \
          "${LINUX_INCLUDE_DIR}/netfilter/xt_TCPMSS.h" \
          "${LINUX_INCLUDE_DIR}/netfilter_ipv4/ipt_ECN.h" \
          "${LINUX_INCLUDE_DIR}/netfilter_ipv4/ipt_TTL.h" \
          "${LINUX_INCLUDE_DIR}/netfilter_ipv6/ip6t_HL.h"
}

finalize_toolchain()
{
    case "$BUILD_OS" in
        darwin)
            # On OSX, always create .dmg files for debugging builds and
            # fix the case issues.
            assemble_dmg

            # Prune out filenames with case conflicts and before make a tarball
            fix_kernel_case_conflicts
            ;;
        linux | freebsd)
            # Linux and FreeBSD don't have the case issues
            create_archive
            ;;
        cygwin)
            # Windows is case insensitive by default, so fix the conflicts
            fix_kernel_case_conflicts
            create_archive
            ;;
    esac
}

checkpoint prepare_environment "$CHECKPOINTS_DIR"
checkpoint checkout_source_code "$CHECKPOINTS_DIR"
checkpoint build_crosstool_ng "$CHECKPOINTS_DIR"
checkpoint prepare_toolchain_build "$CHECKPOINTS_DIR"
checkpoint build_toolchain "$CHECKPOINTS_DIR"
checkpoint save_build_info "$CHECKPOINTS_DIR"
checkpoint cleanup_toolchain "$CHECKPOINTS_DIR"
finalize_toolchain

echo "Done"
