#!/usr/bin/env bash

# Script that should be sourced to setup your environment to cross-compile
# and build Erlang apps for this Grisp build.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: the script grisp-env.sh must be sourced"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# From there we know we are sourced, so we shouldn't call exit (or error)

# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=scripts/utils/env_utils.sh
source "${SCRIPT_DIR}/utils/env_utils.sh"

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

if ! validate_sdk_dir "${GLB_SDK_DIR}"; then
    return $?
fi
if ! setup_cross_env "${GLB_SDK_DIR}"; then
    return $?
fi
if ! setup_erlang_runtime_env "${GLB_SDK_DIR}"; then
    return $?
fi

GRISP_SDK_ROOT="${GLB_SDK_DIR}"
GRISP_SDK_HOST="${GLB_SDK_HOST_DIR}"
GRISP_SDK_IMAGES="${GLB_SDK_DIR}/images"
GRISP_SDK_SYSROOT="${ALLOY_TARGET_SYSROOT}"

export GRISP_SDK_ROOT
export GRISP_SDK_HOST
export GRISP_SDK_IMAGES
export GRISP_SDK_SYSROOT

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
