#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

SCRIPT_HOOK_PATH="$(harness_repo_root)/scripts/buildroot/script_hook.sh"

buildroot_hook_test_make_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"
    mkdir -p "${root_dir}/scripts/buildroot" "${root_dir}/scripts/utils"

    cp "${SCRIPT_HOOK_PATH}" "${root_dir}/scripts/buildroot/script_hook.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/hook_common.sh" "${root_dir}/scripts/utils/hook_common.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_tools.sh" "${root_dir}/scripts/utils/sdk_tools.sh"
    chmod +x "${root_dir}/scripts/buildroot/script_hook.sh"

    printf '%s\n' "${root_dir}"
}

buildroot_hook_test_write_context() {
    local context_path="$1"
    local nugget_dir="$2"
    local hook_entry="$3"

    cat > "${context_path}" <<EOF
export ALLOY_POST_BUILD_HOOKS=(${hook_entry})
export ALLOY_POST_IMAGE_HOOKS=()
export ALLOY_POST_FAKEROOT_HOOKS=()
export ALLOY_NUGGET_CORE_DIR=${nugget_dir}
export ALLOY_NUGGET_CORE_NAME='Core'
export ALLOY_NUGGET_CORE_DESC='Core Nugget'
export ALLOY_NUGGET_CORE_VERSION='1.0.0'
export ALLOY_NUGGET_CORE_FLAVOR=''
alloy_nugget_dir() { local n="\${1^^}"; n="\${n//-/_}"; local v="ALLOY_NUGGET_\${n}_DIR"; printf '%s\\n' "\${!v-}"; }
alloy_nugget_name() { local n="\${1^^}"; n="\${n//-/_}"; local v="ALLOY_NUGGET_\${n}_NAME"; printf '%s\\n' "\${!v-}"; }
alloy_nugget_desc() { local n="\${1^^}"; n="\${n//-/_}"; local v="ALLOY_NUGGET_\${n}_DESC"; printf '%s\\n' "\${!v-}"; }
alloy_nugget_version() { local n="\${1^^}"; n="\${n//-/_}"; local v="ALLOY_NUGGET_\${n}_VERSION"; printf '%s\\n' "\${!v-}"; }
alloy_nugget_flavor() { local n="\${1^^}"; n="\${n//-/_}"; local v="ALLOY_NUGGET_\${n}_FLAVOR"; printf '%s\\n' "\${!v-}"; }
EOF
}

test_buildroot_script_hook_dispatches_post_build_with_common_utils_loaded() {
    local temp_dir root_dir run_dir nugget_dir marker_file output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-dispatch")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    nugget_dir="${temp_dir}/nuggets/core"
    marker_file="${temp_dir}/hook.marker"
    mkdir -p "${run_dir}" "${nugget_dir}/hooks"

    cat > "${nugget_dir}/hooks/post-build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\\n' "\${ALLOY_HOOK_TYPE}" "\${ALLOY_NUGGET}" > "${marker_file}"
EOF
    chmod +x "${nugget_dir}/hooks/post-build.sh"

    buildroot_hook_test_write_context \
        "${run_dir}/alloy_context.sh" \
        "${nugget_dir}" \
        "'core:hooks/post-build.sh'"

    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_MOTHERLODE="${temp_dir}/motherlode" ALLOY_DEBUG=1 \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "INFO: Running post_build hook: core:hooks/post-build.sh" "${output}"
    assert_equals "post_build|core" "$(cat "${marker_file}")"
}

test_buildroot_script_hook_fails_when_context_is_missing() {
    local temp_dir root_dir run_dir output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-missing-context")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    mkdir -p "${run_dir}"
    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_MOTHERLODE="${temp_dir}/motherlode" \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Buildroot hook context is missing" "${output}"
}

test_buildroot_script_hook_warns_and_skips_missing_hook_script() {
    local temp_dir root_dir run_dir nugget_dir output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-missing-script")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    nugget_dir="${temp_dir}/nuggets/core"
    mkdir -p "${run_dir}" "${nugget_dir}/hooks"

    buildroot_hook_test_write_context \
        "${run_dir}/alloy_context.sh" \
        "${nugget_dir}" \
        "'core:hooks/post-build.sh'"
    rm -f "${nugget_dir}/hooks/post-build.sh"
    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_MOTHERLODE="${temp_dir}/motherlode" ALLOY_DEBUG=1 \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "WARN: Skipping missing post_build hook script" "${output}"
}

test_buildroot_script_hook_propagates_hook_failure() {
    local temp_dir root_dir run_dir nugget_dir output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-failure")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    nugget_dir="${temp_dir}/nuggets/core"
    mkdir -p "${run_dir}" "${nugget_dir}/hooks"

    cat > "${nugget_dir}/hooks/post-build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 42
EOF
    chmod +x "${nugget_dir}/hooks/post-build.sh"

    buildroot_hook_test_write_context \
        "${run_dir}/alloy_context.sh" \
        "${nugget_dir}" \
        "'core:hooks/post-build.sh'"
    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_MOTHERLODE="${temp_dir}/motherlode" \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "post_build hook failed: core:hooks/post-build.sh" "${output}"
}

test_buildroot_script_hook_propagates_debug_trace_and_context_vars_to_hook_process() {
    local temp_dir root_dir run_dir nugget_dir marker_file output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-env")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    nugget_dir="${temp_dir}/nuggets/core"
    marker_file="${temp_dir}/hook.env"
    mkdir -p "${run_dir}" "${nugget_dir}/hooks"

    cat > "${nugget_dir}/hooks/post-build.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'HOOK_TYPE=%s\\n' "\${ALLOY_HOOK_TYPE:-}"
    printf 'NUGGET=%s\\n' "\${ALLOY_NUGGET:-}"
    printf 'NUGGET_NAME=%s\\n' "\${ALLOY_NUGGET_NAME:-}"
    printf 'DEBUG=%s\\n' "\${ALLOY_DEBUG:-}"
    printf 'TRACE=%s\\n' "\${ALLOY_TRACE:-}"
    printf 'XTRACE=%s\\n' "\$-"
} > "${marker_file}"
EOF
    chmod +x "${nugget_dir}/hooks/post-build.sh"

    buildroot_hook_test_write_context \
        "${run_dir}/alloy_context.sh" \
        "${nugget_dir}" \
        "'core:hooks/post-build.sh'"
    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_MOTHERLODE="${temp_dir}/motherlode" ALLOY_DEBUG=3 ALLOY_TRACE=true \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "HOOK_TYPE=post_build" "$(cat "${marker_file}")"
    assert_matches "NUGGET=core" "$(cat "${marker_file}")"
    assert_matches "NUGGET_NAME=Core" "$(cat "${marker_file}")"
    assert_matches "DEBUG=3" "$(cat "${marker_file}")"
    assert_matches "TRACE=true" "$(cat "${marker_file}")"
    assert_matches "XTRACE=.*" "$(cat "${marker_file}")"
    assert_matches "Running post_build hook: core:hooks/post-build.sh" "${output}"
}

test_buildroot_script_hook_hook_common_sdk_tools_register_sdk_output() {
    local temp_dir root_dir run_dir nugget_dir output_file output status
    temp_dir="$(harness_make_temp_dir "buildroot-hook-sdk-output")"
    root_dir="$(buildroot_hook_test_make_fixture "${temp_dir}")"
    run_dir="${temp_dir}/run/board/main/scripts"
    nugget_dir="${temp_dir}/nuggets/core"
    mkdir -p "${run_dir}" "${nugget_dir}/hooks"

    cat > "${nugget_dir}/hooks/post-build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh"
artifact_dir="${O}/generated"
mkdir -p "${artifact_dir}"
artifact_file="${artifact_dir}/sdk-payload.bin"
printf 'payload\n' > "${artifact_file}"
alloy_sdk_add_output "sdk_payload" "${artifact_file}"
EOF
    chmod +x "${nugget_dir}/hooks/post-build.sh"

    buildroot_hook_test_write_context \
        "${run_dir}/alloy_context.sh" \
        "${nugget_dir}" \
        "'core:hooks/post-build.sh'"
    ln -s "${root_dir}/scripts/buildroot/script_hook.sh" "${run_dir}/post-build.sh"

    output="$(ALLOY_ROOT_DIR="${root_dir}" \
        O="${temp_dir}/workspace" \
        "${run_dir}/post-build.sh" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    output_file="${temp_dir}/workspace/.sdk_outputs/sdk_payload"
    assert_status_code 0 "[[ -f '${output_file}' ]]"
    assert_status_code 0 "grep -Fq '${temp_dir}/workspace/generated/sdk-payload.bin' '${output_file}'"
}
