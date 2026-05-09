#!/usr/bin/env bash

if [[ -n "${ALLOY_HOOK_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
ALLOY_HOOK_COMMON_SH_LOADED=1

hook_prefix_hook_type="${ALLOY_HOOK_TYPE:-hook}"
hook_prefix_nugget="${ALLOY_NUGGET:-global}"
ALLOY_LOG_PREFIX="alloy:${hook_prefix_hook_type}:${hook_prefix_nugget}"
export ALLOY_LOG_PREFIX

# shellcheck source=scripts/utils/debug_tools.sh
source "${ALLOY_ROOT_DIR}/scripts/utils/debug_tools.sh"

if [[ "${ALLOY_TRACE:-false}" == "true" ]]; then
    set -x
fi

case "${ALLOY_HOOK_TYPE:-}" in
    pre_build|post_build|post_image|post_fakeroot)
        # shellcheck source=scripts/utils/sdk_tools.sh
        source "${ALLOY_ROOT_DIR}/scripts/utils/sdk_tools.sh"
        ;;
    *)
        ;;
esac
