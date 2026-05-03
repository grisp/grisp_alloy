#!/usr/bin/env bash

if [[ -n "${ALLOY_HOOK_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
ALLOY_HOOK_COMMON_SH_LOADED=1

if [[ "${ALLOY_TRACE:-false}" == "true" ]]; then
    set -x
fi

alloy_hook_debug() {
    if [[ "${ALLOY_DEBUG:-0}" =~ ^[0-9]+$ ]] && [[ "${ALLOY_DEBUG}" -ge 2 ]]; then
        printf 'DEBUG: %s\n' "$*" >&2
    fi
}

alloy_hook_info() {
    printf 'INFO: %s\n' "$*" >&2
}

alloy_hook_warn() {
    printf 'WARN: %s\n' "$*" >&2
}

alloy_hook_die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 2
}

case "${ALLOY_HOOK_TYPE:-}" in
    pre_build|post_build|post_image|post_fakeroot)
        # shellcheck source=scripts/utils/sdk_tools.sh
        source "${ALLOY_ROOT_DIR}/scripts/utils/sdk_tools.sh"
        ;;
    *)
        ;;
esac
