#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE_PATH}" ]]; do
    SOURCE_DIR="$(cd "$(dirname "${SOURCE_PATH}")" && pwd -P)"
    SOURCE_PATH="$(readlink "${SOURCE_PATH}")"
    if [[ "${SOURCE_PATH}" != /* ]]; then
        SOURCE_PATH="${SOURCE_DIR}/${SOURCE_PATH}"
    fi
done
SCRIPT_DIR="$(cd "$(dirname "${SOURCE_PATH}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"

hook_name="$(basename "${0}")"
hook_type="${hook_name%.sh}"
hook_type="${hook_type//-/_}"

case "${hook_type}" in
    post_build)
        hook_array_name="ALLOY_POST_BUILD_HOOKS"
        ;;
    post_image)
        hook_array_name="ALLOY_POST_IMAGE_HOOKS"
        ;;
    post_fakeroot)
        hook_array_name="ALLOY_POST_FAKEROOT_HOOKS"
        ;;
    *)
        fail "Unsupported Buildroot hook wrapper invocation: ${hook_name}"
        ;;
esac

context_file="$(cd "$(dirname "${0}")" && pwd -P)/alloy_context.sh"
[[ -f "${context_file}" ]] ||
    fail "Buildroot hook context is missing: ${context_file}"

# shellcheck disable=SC1090  # context file is generated per target by smelterl.
source "${context_file}"

if ! declare -p "${hook_array_name}" >/dev/null 2>&1; then
    log_info "No ${hook_type} hooks declared in context (${hook_array_name})."
    exit 0
fi

export ALLOY_HOOK_TYPE="${hook_type}"
eval "hook_entries=(\"\${${hook_array_name}[@]}\")"

for hook_entry in "${hook_entries[@]}"; do
    [[ "${hook_entry}" == *:* ]] ||
        fail "Invalid hook entry in ${hook_array_name}: ${hook_entry}"

    nugget_id="${hook_entry%%:*}"
    script_relpath="${hook_entry#*:}"
    [[ -n "${nugget_id}" ]] || fail "Invalid hook entry with empty nugget id: ${hook_entry}"
    [[ -n "${script_relpath}" ]] || fail "Invalid hook entry with empty script path: ${hook_entry}"

    nugget_dir="$(alloy_nugget_dir "${nugget_id}")"
    [[ -n "${nugget_dir}" ]] ||
        fail "Hook context is missing nugget directory for '${nugget_id}'"

    hook_script="${nugget_dir}/${script_relpath}"
    if [[ ! -f "${hook_script}" ]]; then
        log_warn "Skipping missing ${hook_type} hook script: ${hook_script}"
        continue
    fi

    export ALLOY_NUGGET="${nugget_id}"
    export ALLOY_NUGGET_DIR="${nugget_dir}"
    export ALLOY_NUGGET_NAME="$(alloy_nugget_name "${nugget_id}")"
    export ALLOY_NUGGET_DESC="$(alloy_nugget_desc "${nugget_id}")"
    export ALLOY_NUGGET_VERSION="$(alloy_nugget_version "${nugget_id}")"
    export ALLOY_NUGGET_FLAVOR="$(alloy_nugget_flavor "${nugget_id}")"

    log_info "Running ${hook_type} hook: ${nugget_id}:${script_relpath}"
    if ! bash "${hook_script}" "$@"; then
        fail "${hook_type} hook failed: ${nugget_id}:${script_relpath}"
    fi
done
