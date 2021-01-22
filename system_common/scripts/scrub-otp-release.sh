#!/bin/sh

# Remove or minimize files in an Erlang/OTP release directory
# in preparation for use packaging in a Grisp firmware image.
#
# scrub-otp-release.sh <Erlang/OTP release directory>

set -e
export LC_ALL=C

SCRIPT_NAME=$(basename "$0")
RELEASE_DIR="$1"

# Check that the release directory exists
if [ ! -d "$RELEASE_DIR" ]; then
    echo "$SCRIPT_NAME: ERROR: Missing Erlang/OTP release directory: ($RELEASE_DIR)"
    exit 1
fi

if [ ! -d "$RELEASE_DIR/lib" ] || [ ! -d "$RELEASE_DIR/releases" ]; then
    echo "$SCRIPT_NAME: ERROR: Expecting '$RELEASE_DIR' to contain 'lib' and 'releases' subdirectories"
    exit 1
fi

STRIP="$CROSSCOMPILE-strip"
READELF="$CROSSCOMPILE-readelf"
if [ ! -e "$STRIP" ] || [ ! -e "$READELF" ]; then
    echo "$SCRIPT_NAME: ERROR: can't find strip and readelf commands for cross-compilation"
    echo "  Expecting \$CROSSCOMPILE to be set. Did you source grisp-env.sh ?"
    echo "    strip=$STRIP"
    echo "    readelf=$READELF"
    echo
  exit 1
fi

# Clean up the Erlang release of all the files that we don't need.
# The user should create their releases without source code
# unless they want really big images..
rm -fr "${RELEASE_DIR:?}/bin" "$RELEASE_DIR"/erts-*

# Delete empty directories
find "$RELEASE_DIR" -type d -empty -delete

# Delete any temp files, release tarballs, etc from the base release directory
# Nothing is supposed to be there.
find "$RELEASE_DIR" -maxdepth 1 -type f -delete

# Clean up the releases directory
find "$RELEASE_DIR/releases" \( -name "*.sh" \
                                 -o -name "*.bat" \
                                 -o -name "*.ps1" \
                                 -o -name "*gz" \
                                 -o -name "start.boot" \
                                 -o -name "start_clean.boot" \
                                 -o -name "*.script" \
                                 \) -delete

#
# Scrub the executables
#

executable_type()
{
    FILE=$1

    # Try readelf first, since it's output seems more trustworthy for executables
    READELF_OUTPUT=$("$READELF" -h "$FILE" 2>/dev/null || true)
    if [ "$READELF_OUTPUT" ]; then
        ELF_MACHINE=$(echo "$READELF_OUTPUT" | sed -E -e '/^  Machine: +(.+)/!d; s//\1/;' | head -1)
        ELF_FLAGS=$(echo "$READELF_OUTPUT" | sed -E -e '/^  Flags: +(.+)/!d; s//\1/;' | head -1)

        if [ -z "$ELF_MACHINE" ]; then
            echo "$SCRIPT_NAME: ERROR: Didn't expect empty machine field in ELF header in $FILE." 1>&2
            exit 1
        fi
        echo "readelf:$ELF_MACHINE;$ELF_FLAGS"
    else
        # readelf didn't work, so try file and guess at things that will cause problems
        FILE_OUTPUT=$(file -b -h "$FILE")
        case "$FILE_OUTPUT" in
            *shared*library*)
                echo "file:$FILE_OUTPUT"
                ;;

            *x86_64*)
                echo "file:$FILE_OUTPUT"
                ;;

            *)
                echo "portable"
                ;;
        esac
    fi
}

get_expected_executable_type()
{
    # Compile a trivial C program with the crosscompiler
    # so that we know what the `file` output should look like.
    tmpfile=$(mktemp /tmp/scrub-otp-release.XXXXXX)
    echo "int main() {}" | "$CROSSCOMPILE-gcc" -x c -o "$tmpfile" -
    executable_type "$tmpfile"
    rm "$tmpfile"
}

EXECUTABLES=$(find "$RELEASE_DIR" -type f -perm -100)
EXPECTED_TYPE=$(get_expected_executable_type)

for EXECUTABLE in $EXECUTABLES; do
    TYPE=$(executable_type "$EXECUTABLE")
    if [ "$TYPE" != "portable" ]; then
        # Verify that the executable was compiled for the target
        if [ "$TYPE" != "$EXPECTED_TYPE" ]; then
            echo "$SCRIPT_NAME: ERROR: Unexpected executable format for '$EXECUTABLE'"
            echo
            echo "Got:"
            echo " $TYPE"
            echo
            echo "Expecting:"
            echo " $EXPECTED_TYPE"
            echo
            echo "This file was compiled for the host or a different target and probably"
            echo "will not work."
            echo
            exit 1
        fi

        # Strip debug information from ELF binaries
        # Symbols are still available to the user in the release directory.
        $STRIP "$EXECUTABLE"
    fi
done
