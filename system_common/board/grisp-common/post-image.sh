#!/usr/bin/env bash

set -e

source "$( dirname "$0" )/../../../scripts/common.sh" "$GRISP_TARGET_NAME"

FWUP_CONFIG="$GLB_TARGET_SYSTEM_DIR/fwup.conf"
if [[ ! -f $FWUP_CONFIG ]]; then
    echo "ERROR: fwup config not found: $FWUP_CONFIG"
    exit 1
fi

if [[ ! -d $BINARIES_DIR ]]; then
    echo "ERROR: Output directory not found: $BINARIES_DIR"
fi

cp -f "$FWUP_CONFIG" "$BINARIES_DIR"
